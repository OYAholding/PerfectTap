# PerfectTap — idempotent App Store Connect IAP reconciler.
#
# Desired state: fastlane/iap/catalog.json (+ review notes + review screenshots).
# Actual state:  App Store Connect API (in-app purchases v2).
#
# The reconciler only ever ADDS what is missing or UPDATES editable metadata to
# match the catalog. It never deletes a product, never changes a product type or
# product ID, never submits anything for review and never touches app versions.
# Dry-run is the default; writes need `confirm_create:true` AND PT_CONFIRM=yes
# (see the `iap_reconcile` lane). After writes it re-reads everything and fails
# if any difference remains.
#
# No credentials are read here: the caller passes an API adapter that already
# carries a short-lived JWT (Spaceship token from the ASC API key).

require "digest"
require "json"
require "net/http"

module PTIap
  ASC_HOST = "https://api.appstoreconnect.apple.com".freeze
  # States in which Apple accepts metadata edits through the API.
  EDITABLE_STATES = %w[MISSING_METADATA READY_TO_SUBMIT DEVELOPER_ACTION_NEEDED REJECTED].freeze
  REVIEW_NOTE_MAX = 4000
  REQUIRED_IDS = %w[
    com.perfecttap.coins.500 com.perfecttap.coins.1200 com.perfecttap.coins.3000 com.perfecttap.coins.8000
    com.perfecttap.removeads
    com.perfecttap.skin.neonpulse com.perfecttap.skin.liquidchrome com.perfecttap.skin.glitchmode com.perfecttap.skin.cosmicgold
  ].freeze

  # ---- Desired state -------------------------------------------------------

  def self.desired_products(catalog, review_note, screenshot_root)
    ids = catalog["products"].map { |p| p["productId"] }
    raise "catalog product IDs changed: #{(ids - REQUIRED_IDS) + (REQUIRED_IDS - ids)}" unless ids.sort == REQUIRED_IDS.sort
    raise "review note exceeds #{REVIEW_NOTE_MAX} characters" if review_note.length > REVIEW_NOTE_MAX
    removeads = catalog["products"].find { |p| p["productId"] == "com.perfecttap.removeads" }
    raise "removeads display name must be 'Remove Forced Ads'" unless removeads["displayName"] == "Remove Forced Ads"
    locale = catalog["locale"] || "en-US"
    availability = catalog["availability"] || { "allTerritories" => true, "availableInNewTerritories" => true }
    catalog["products"].map do |p|
      shot = File.expand_path(p["reviewScreenshot"], screenshot_root)
      {
        product_id: p["productId"],
        type: p["type"],
        reference_name: p["referenceName"],
        family_sharable: false,
        review_note: review_note,
        locale: locale,
        display_name: p["displayName"],
        description: p["description"],
        price_usd: p["priceUSD"],
        availability: availability,
        screenshot_path: shot,
        screenshot_md5: File.exist?(shot) ? Digest::MD5.file(shot).hexdigest : nil,
        screenshot_size: File.exist?(shot) ? File.size(shot) : nil
      }
    end
  end

  # ---- Actual state --------------------------------------------------------

  def self.list_iaps(api, app_id)
    api.get_all("/v1/apps/#{app_id}/inAppPurchasesV2?limit=200")
  end

  def self.remote_state(api, iap)
    id = iap["id"]
    attrs = iap["attributes"] || {}
    locs = api.get_all("/v2/inAppPurchases/#{id}/inAppPurchaseLocalizations?limit=50")
    usd = nil
    schedule = api.get_optional("/v2/inAppPurchases/#{id}/iapPriceSchedule")
    if schedule && schedule["data"]
      prices = api.get_optional("/v1/inAppPurchasePriceSchedules/#{schedule['data']['id']}/manualPrices" \
                                "?filter[territory]=USA&include=inAppPurchasePricePoint&limit=50")
      points = (prices && prices["included"] || []).select { |i| i["type"] == "inAppPurchasePricePoints" }
      usd = points.map { |pp| pp.dig("attributes", "customerPrice") }.compact.first
    end
    availability = api.get_optional("/v2/inAppPurchases/#{id}/inAppPurchaseAvailability")
    territories = nil
    if availability && availability["data"]
      territories = api.get_all("/v1/inAppPurchaseAvailabilities/#{availability['data']['id']}/availableTerritories?limit=200")
                       .map { |t| t["id"] }
    end
    shot = api.get_optional("/v2/inAppPurchases/#{id}/appStoreReviewScreenshot")
    shot_attrs = shot && shot["data"] ? shot["data"]["attributes"] : nil
    {
      id: id,
      state: attrs["state"],
      type: attrs["inAppPurchaseType"],
      reference_name: attrs["name"],
      review_note: attrs["reviewNote"],
      family_sharable: attrs["familySharable"],
      localizations: locs.to_h { |l| [l.dig("attributes", "locale"), { id: l["id"], name: l.dig("attributes", "name"), description: l.dig("attributes", "description") }] },
      price_usd: usd,
      availability_id: availability && availability["data"] ? availability["data"]["id"] : nil,
      available_new: availability && availability["data"] ? availability["data"].dig("attributes", "availableInNewTerritories") : nil,
      territories: territories,
      screenshot: shot_attrs && { id: shot["data"]["id"], md5: shot_attrs["sourceFileChecksum"], state: shot_attrs.dig("assetDeliveryState", "state") }
    }
  end

  # ---- Diff ----------------------------------------------------------------

  def self.price_equal?(a, b)
    return false if a.nil? || b.nil?
    BigDecimal(a.to_s) == BigDecimal(b.to_s)
  rescue ArgumentError
    false
  end

  # Returns [actions, blockers]. Actions are idempotent steps; blockers are
  # differences the reconciler must not fix (type change, locked state).
  def self.diff(desired, remote, all_territories)
    actions = []
    blockers = []
    unless remote
      actions << { step: :create, detail: "#{desired[:type]} '#{desired[:reference_name]}'" }
      actions << { step: :localization, detail: "#{desired[:locale]} '#{desired[:display_name]}'" }
      actions << { step: :price, detail: "USD #{desired[:price_usd]}" }
      actions << { step: :availability, detail: availability_label(desired) }
      actions << { step: :screenshot, detail: File.basename(desired[:screenshot_path]) }
      return [actions, blockers]
    end
    blockers << "type is #{remote[:type]}, catalog says #{desired[:type]} (Apple never allows a type change)" if remote[:type] != desired[:type]
    editable = EDITABLE_STATES.include?(remote[:state])
    meta = []
    meta << "reference name" if remote[:reference_name] != desired[:reference_name]
    meta << "review note" if remote[:review_note].to_s.strip != desired[:review_note].strip
    meta << "family sharing" if remote[:family_sharable] != desired[:family_sharable]
    actions << { step: :update, detail: meta.join(", ") } unless meta.empty?
    loc = remote[:localizations][desired[:locale]]
    if loc.nil? || loc[:name] != desired[:display_name] || loc[:description] != desired[:description]
      actions << { step: :localization, detail: loc ? "update #{desired[:locale]}" : "add #{desired[:locale]}" }
    end
    unless price_equal?(remote[:price_usd], desired[:price_usd])
      actions << { step: :price, detail: "USD #{remote[:price_usd] || 'none'} -> #{desired[:price_usd]}" }
    end
    want_territories = desired[:availability]["allTerritories"] ? all_territories : Array(desired[:availability]["territories"])
    if remote[:availability_id].nil? || remote[:territories].to_a.sort != want_territories.sort ||
       remote[:available_new] != desired[:availability]["availableInNewTerritories"]
      actions << { step: :availability, detail: availability_label(desired) }
    end
    if remote[:screenshot].nil? || remote[:screenshot][:md5] != desired[:screenshot_md5]
      actions << { step: :screenshot, detail: remote[:screenshot] ? "replace (checksum differs)" : "upload" }
    end
    if !editable && actions.any?
      blockers << "state #{remote[:state]} is not editable through the API; #{actions.map { |a| a[:step] }.join(', ')} left unchanged"
      actions = []
    end
    [actions, blockers]
  end

  def self.availability_label(desired)
    a = desired[:availability]
    scope = a["allTerritories"] ? "all territories" : Array(a["territories"]).join(",")
    "#{scope}, new territories: #{a['availableInNewTerritories']}"
  end

  # ---- Price points --------------------------------------------------------

  # IAP price points exist per product, so for a product that does not exist yet
  # the lookup uses the app price grid for USA (same USD tiers) as a read-only
  # preview; the real IAP price point ID is resolved after creation.
  def self.usd_price_points_for_iap(api, iap_id)
    api.get_all("/v2/inAppPurchases/#{iap_id}/pricePoints?filter[territory]=USA&limit=200")
       .to_h { |pp| [BigDecimal(pp.dig("attributes", "customerPrice")), pp["id"]] }
  end

  def self.usd_price_grid_preview(api, app_id)
    api.get_all("/v1/apps/#{app_id}/appPricePoints?filter[territory]=USA&limit=200")
       .map { |pp| BigDecimal(pp.dig("attributes", "customerPrice")) }
  end

  # ---- Writes (only reached with confirm_create:true + PT_CONFIRM=yes) -----

  def self.apply!(api, app_id, desired, remote, actions, all_territories, log)
    iap_id = remote && remote[:id]
    actions.each do |action|
      case action[:step]
      when :create
        res = api.write(:post, "/v2/inAppPurchases", { data: {
          type: "inAppPurchases",
          attributes: { name: desired[:reference_name], productId: desired[:product_id],
                        inAppPurchaseType: desired[:type], reviewNote: desired[:review_note],
                        familySharable: desired[:family_sharable] },
          relationships: { app: { data: { type: "apps", id: app_id } } } } })
        iap_id = res.dig("data", "id")
        raise "create returned no id for #{desired[:product_id]}" unless iap_id
      when :update
        api.write(:patch, "/v2/inAppPurchases/#{iap_id}", { data: { type: "inAppPurchases", id: iap_id,
          attributes: { name: desired[:reference_name], reviewNote: desired[:review_note],
                        familySharable: desired[:family_sharable] } } })
      when :localization
        existing = api.get_all("/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations?limit=50")
                      .find { |l| l.dig("attributes", "locale") == desired[:locale] }
        if existing
          api.write(:patch, "/v1/inAppPurchaseLocalizations/#{existing['id']}", { data: {
            type: "inAppPurchaseLocalizations", id: existing["id"],
            attributes: { name: desired[:display_name], description: desired[:description] } } })
        else
          api.write(:post, "/v1/inAppPurchaseLocalizations", { data: {
            type: "inAppPurchaseLocalizations",
            attributes: { locale: desired[:locale], name: desired[:display_name], description: desired[:description] },
            relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } } } })
        end
      when :price
        points = usd_price_points_for_iap(api, iap_id)
        point_id = points[BigDecimal(desired[:price_usd])]
        raise "no USD price point #{desired[:price_usd]} for #{desired[:product_id]}" unless point_id
        api.write(:post, "/v1/inAppPurchasePriceSchedules", {
          data: { type: "inAppPurchasePriceSchedules", relationships: {
            inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
            baseTerritory: { data: { type: "territories", id: "USA" } },
            manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${usd}" }] } } },
          included: [{ type: "inAppPurchasePrices", id: "${usd}", attributes: { startDate: nil },
                       relationships: { inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: point_id } } } }] })
      when :availability
        terr = desired[:availability]["allTerritories"] ? all_territories : Array(desired[:availability]["territories"])
        api.write(:post, "/v1/inAppPurchaseAvailabilities", { data: {
          type: "inAppPurchaseAvailabilities",
          attributes: { availableInNewTerritories: desired[:availability]["availableInNewTerritories"] },
          relationships: { inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
                           availableTerritories: { data: terr.map { |t| { type: "territories", id: t } } } } } })
      when :screenshot
        upload_screenshot!(api, iap_id, desired)
      end
      log.call("#{desired[:product_id]}: #{action[:step]} done")
    end
    iap_id
  end

  def self.upload_screenshot!(api, iap_id, desired)
    path = desired[:screenshot_path]
    raise "missing review screenshot #{path}" unless File.exist?(path)
    old = api.get_optional("/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot")
    api.write(:delete, "/v1/inAppPurchaseAppStoreReviewScreenshots/#{old['data']['id']}", nil) if old && old["data"]
    reserve = api.write(:post, "/v1/inAppPurchaseAppStoreReviewScreenshots", { data: {
      type: "inAppPurchaseAppStoreReviewScreenshots",
      attributes: { fileName: File.basename(path), fileSize: desired[:screenshot_size] },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } } } })
    shot_id = reserve.dig("data", "id")
    bytes = File.binread(path)
    reserve.dig("data", "attributes", "uploadOperations").to_a.each do |op|
      chunk = bytes.byteslice(op["offset"], op["length"])
      api.upload(op["method"], op["url"], op["requestHeaders"].to_a.to_h { |h| [h["name"], h["value"]] }, chunk)
    end
    api.write(:patch, "/v1/inAppPurchaseAppStoreReviewScreenshots/#{shot_id}", { data: {
      type: "inAppPurchaseAppStoreReviewScreenshots", id: shot_id,
      attributes: { uploaded: true, sourceFileChecksum: desired[:screenshot_md5] } } })
  end

  # ---- HTTP adapter --------------------------------------------------------

  # Thin JSON:API client. `token` is a callable returning a fresh bearer JWT.
  class Api
    def initialize(token, on_error)
      @token = token
      @on_error = on_error
    end

    def get(path)
      res, body = request(Net::HTTP::Get, path)
      @on_error.call("GET #{strip(path)} -> HTTP #{res.code} #{errors(body)}") unless res.code.to_i == 200
      body
    end

    def get_optional(path)
      res, body = request(Net::HTTP::Get, path)
      return nil if res.code.to_i == 404
      @on_error.call("GET #{strip(path)} -> HTTP #{res.code} #{errors(body)}") unless res.code.to_i == 200
      body
    end

    def get_all(path)
      out = []
      next_path = path
      while next_path
        body = get(next_path)
        out.concat(Array(body["data"]))
        nxt = body.dig("links", "next")
        next_path = nxt && nxt.sub(ASC_HOST, "")
      end
      out
    end

    def write(method, path, payload)
      klass = { post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
      res, body = request(klass, path, payload)
      @on_error.call("#{method.upcase} #{strip(path)} -> HTTP #{res.code} #{errors(body)}") unless res.code.to_i.between?(200, 299)
      body
    end

    def upload(method, url, headers, data)
      uri = URI(url)
      klass = method.to_s.upcase == "PUT" ? Net::HTTP::Put : Net::HTTP::Post
      req = klass.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = data
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      @on_error.call("screenshot upload -> HTTP #{res.code}") unless res.code.to_i.between?(200, 299)
    end

    private

    def request(klass, path, payload = nil)
      uri = URI("#{ASC_HOST}#{path}")
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{@token.call}"
      if payload
        req["Content-Type"] = "application/json"
        req.body = JSON.dump(payload)
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      body = res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue {})
      [res, body]
    end

    def strip(path)
      path.split("?").first
    end

    def errors(body)
      Array(body["errors"]).map { |e| e["detail"] || e["title"] }.join("; ")
    end
  end
end

require "bigdecimal"
