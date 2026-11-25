# Offline tests for the IAP reconciler diff (no network, no credentials).
#   ruby fastlane/test/iap_reconciler_test.rb
require "minitest/autorun"
require "json"
require_relative "../iap_reconciler"

class IapReconcilerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def catalog
    JSON.parse(File.read(File.join(ROOT, "iap/catalog.json")))
  end

  def desired
    PTIap.desired_products(catalog, File.read(File.join(ROOT, "iap/review-notes.en-US.txt")).strip, File.join(ROOT, "iap"))
  end

  def in_sync_remote(d, territories)
    { id: "1", state: "READY_TO_SUBMIT", type: d[:type], reference_name: d[:reference_name],
      review_note: d[:review_note], family_sharable: false,
      localizations: { d[:locale] => { id: "l", name: d[:display_name], description: d[:description] } },
      price_usd: d[:price_usd], availability_id: "a", available_new: true, territories: territories,
      screenshot: { id: "s", md5: d[:screenshot_md5], state: "COMPLETE" } }
  end

  def test_catalog_keeps_the_nine_product_ids_and_draft_prices
    prices = desired.to_h { |d| [d[:product_id], d[:price_usd]] }
    assert_equal({ "com.perfecttap.coins.500" => "0.99", "com.perfecttap.coins.1200" => "1.99",
                   "com.perfecttap.coins.3000" => "3.99", "com.perfecttap.coins.8000" => "9.99",
                   "com.perfecttap.removeads" => "2.99", "com.perfecttap.skin.neonpulse" => "1.99",
                   "com.perfecttap.skin.liquidchrome" => "1.99", "com.perfecttap.skin.glitchmode" => "1.99",
                   "com.perfecttap.skin.cosmicgold" => "1.99" }, prices)
    assert_equal "Remove Forced Ads", desired.find { |d| d[:product_id] == "com.perfecttap.removeads" }[:display_name]
  end

  def test_review_note_fits_and_explains_testing
    note = desired.first[:review_note]
    assert_operator note.length, :<=, PTIap::REVIEW_NOTE_MAX
    assert_match(/sandbox/i, note)
    assert_match(/rewarded/i, note)
    assert_match(/optional/i, note)
  end

  def test_missing_product_plans_full_creation
    actions, blockers = PTIap.diff(desired.first, nil, %w[USA])
    assert_equal %i[create localization price availability screenshot], actions.map { |a| a[:step] }
    assert_empty blockers
  end

  def test_in_sync_product_needs_nothing
    terr = %w[USA GBR]
    desired.each do |d|
      actions, blockers = PTIap.diff(d, in_sync_remote(d, terr), terr)
      assert_empty actions, d[:product_id]
      assert_empty blockers
    end
  end

  def test_drift_is_planned_but_type_change_is_a_blocker
    d = desired.first
    terr = %w[USA]
    remote = in_sync_remote(d, terr).merge(price_usd: "4.99", review_note: "old",
                                           localizations: {}, screenshot: nil)
    actions, = PTIap.diff(d, remote, terr)
    assert_equal %i[update localization price screenshot], actions.map { |a| a[:step] }
    _, blockers = PTIap.diff(d, in_sync_remote(d, terr).merge(type: "NON_CONSUMABLE"), terr)
    refute_empty blockers
  end

  def test_locked_state_is_never_modified
    d = desired.first
    remote = in_sync_remote(d, %w[USA]).merge(state: "WAITING_FOR_REVIEW", price_usd: "4.99")
    actions, blockers = PTIap.diff(d, remote, %w[USA])
    assert_empty actions
    assert_match(/not editable/, blockers.join)
  end

  def test_price_comparison_is_numeric
    assert PTIap.price_equal?("0.99", "0.990")
    refute PTIap.price_equal?("0.99", nil)
  end
end
