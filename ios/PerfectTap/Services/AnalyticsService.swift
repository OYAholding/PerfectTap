import Foundation
import FirebaseAnalytics

// MARK: - AnalyticsService
// Lightweight wrapper around Firebase Analytics.
// Centralizes all event logging so we can swap providers later.

enum AnalyticsService {

    // MARK: - Game Events

    static func logGameStart(mode: String) {
        Analytics.logEvent("game_start", parameters: [
            "mode": mode
        ])
    }

    static func logGameEnd(mode: String, score: Int, maxCombo: Int, coinsEarned: Int) {
        Analytics.logEvent("game_end", parameters: [
            "mode": mode,
            "score": score,
            "max_combo": maxCombo,
            "coins_earned": coinsEarned
        ])
    }

    static func logReviveUsed(mode: String) {
        Analytics.logEvent("revive_used", parameters: [
            "mode": mode
        ])
    }

    // MARK: - Economy Events

    static func logCoinsPurchased(packId: String, amount: Int) {
        Analytics.logEvent(AnalyticsEventPurchase, parameters: [
            "pack_id": packId,
            "coins": amount
        ])
    }

    static func logShopItemBought(itemId: String, price: Int) {
        Analytics.logEvent(AnalyticsEventSpendVirtualCurrency, parameters: [
            AnalyticsParameterItemID: itemId,
            AnalyticsParameterValue: price,
            AnalyticsParameterVirtualCurrencyName: "coins"
        ])
    }

    static func logAdWatched(placement: String, reward: Int) {
        Analytics.logEvent("ad_reward_earned", parameters: [
            "placement": placement,
            "reward": reward
        ])
    }

    // MARK: - Progression Events

    static func logLevelUp(newLevel: Int) {
        Analytics.logEvent(AnalyticsEventLevelUp, parameters: [
            AnalyticsParameterLevel: newLevel
        ])
    }

    static func logAchievementUnlocked(achievementId: String) {
        Analytics.logEvent(AnalyticsEventUnlockAchievement, parameters: [
            AnalyticsParameterAchievementID: achievementId
        ])
    }

    // MARK: - Navigation Events

    static func logScreenView(screen: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screen
        ])
    }

    static func logModeSelected(mode: String) {
        Analytics.logEvent("mode_selected", parameters: [
            "mode": mode
        ])
    }

    static func logSeasonRewardUnavailable(category: String, rewardId: String, tier: Int) {
        Analytics.logEvent("season_reward_unavailable", parameters: [
            "category": category,
            "reward_id": rewardId,
            "tier": tier
        ])
    }
}
