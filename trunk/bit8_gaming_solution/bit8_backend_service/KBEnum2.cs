using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8_utilities.ImpactTool
{
    public class KnowledgeBase : System.Attribute
    {

        public KnowledgeBase(params string[] kbEntities)
        {
           
        }
         
        public static class Generic
        {
            public const string NoTag = "NoTag";
        }

        
		public static class Operations 
		{
 			public const string ManageAllPlayerCards = "ManageAllPlayerCards";
			public const string ViewAllPlayerCards = "ViewAllPlayerCards";
			public const string DefaultPlayLimits = "DefaultPlayLimits";
			public const string LimitNotificationRules = "LimitNotificationRules";
			public const string ManageAllPlatforms = "ManageAllPlatforms";
			public const string PaymentLimitsPage = "PaymentLimitsPage";
			public const string PaymentMethodLimits = "PaymentMethodLimits";
			public const string ProfanityFilter = "ProfanityFilter";
			public const string SecretQuestionManagement = "SecretQuestionManagement";
			public const string SecretQuestionTranslation = "SecretQuestionTranslation";
			public const string AssignRemoveCurrencies = "AssignRemoveCurrencies";
			public const string ChangeExchangeRates = "ChangeExchangeRates";
			public const string ViewAllAssignedCurrencies = "ViewAllAssignedCurrencies";
			public const string InactivityFeeSettings = "InactivityFeeSettings";
			public const string CountriesManageAll = "CountriesManageAll";
			public const string CountryRestrictions = "CountryRestrictions";
			public const string TaxSettings = "TaxSettings";
			public const string AffiliatesDataTransfer = "AffiliatesDataTransfer";
			public const string ManageAffiliates = "ManageAffiliates";
			public const string CreditDebitNotes = "CreditDebitNotes";
		}

		public static class GameVerticals 
		{
 			public const string Hierarchy = "Hierarchy";
			public const string BetLimitProfileValues = "BetLimitProfileValues";
			public const string BetLimitProfiles = "BetLimitProfiles";
			public const string CasinoGameWeights = "CasinoGameWeights";
			public const string CurrencyProfiles = "CurrencyProfiles";
			public const string LinkProfiles = "LinkProfiles";
			public const string LotteryGameWeightsProfiles = "LotteryGameWeightsProfiles";
			public const string PaymentProfileLinking = "PaymentProfileLinking";
			public const string PaymentRestrictionProfiles = "PaymentRestrictionProfiles";
			public const string SportsPoolGameWeightProfiles = "SportsPoolGameWeightProfiles";
			public const string SportsbookWeights = "SportsbookWeights";
			public const string AssignGameCategories = "AssignGameCategories";
			public const string ManageGames = "ManageGames";
			public const string ManageProviderGames = "ManageProviderGames";
			public const string AutoplaySubscriptions = "AutoplaySubscriptions";
			public const string GamingTransactions = "GamingTransactions";
			public const string OpenTransactions = "OpenTransactions";
			public const string ReservedFunds = "ReservedFunds";
			public const string TransactionResolution = "TransactionResolution";
		}

		public static class FraudPayments 
		{
 			public const string DepositAuthorization = "DepositAuthorization";
			public const string ManageWinClassifications = "ManageWinClassifications";
			public const string ManualPaymentProcessing = "ManualPaymentProcessing";
			public const string PaymentMethodManagement = "PaymentMethodManagement";
			public const string WinAuthorization = "WinAuthorization";
			public const string WithdrawalAuthorization = "WithdrawalAuthorization";
			public const string ManageWithdrawClasifications = "ManageWithdrawClasifications";
			public const string FraudEngine = "FraudEngine";
			public const string FraudRuleEngine = "FraudRuleEngine";
			public const string PaymentMethodRiskGroups = "PaymentMethodRiskGroups";
			public const string CountryBanningByIP = "CountryBanningByIP";
			public const string FraudBanningByIP = "FraudBanningByIP";
			public const string ManageClassifications = "ManageClassifications";
			public const string ManageIINCodes = "ManageIINCodes";
			public const string PlayerSegments = "PlayerSegments";
			public const string TagLanguagesToCountries = "TagLanguagesToCountries";
			public const string ChargebackWatch = "ChargebackWatch";
			public const string DepositWatch = "DepositWatch";
			public const string ExpiredDocuments = "ExpiredDocuments";
			public const string FraudCategories = "FraudCategories";
			public const string FraudFailedDepositWatch = "FraudFailedDepositWatch";
			public const string FraudRuleWatch = "FraudRuleWatch";
			public const string HitList = "HitList";
			public const string IPManagement = "IPManagement";
			public const string KYC = "KYC";
			public const string ManageFailedDeposits = "ManageFailedDeposits";
			public const string PaymentMethodsByCountry = "PaymentMethodsByCountry";
			public const string PlayerWatch = "PlayerWatch";
		}

		public static class CampaignManagement 
		{
 			public const string Tournaments = "Tournaments";
			public const string TournamentsAwarding = "TournamentsAwarding";
			public const string PromotionStatistics = "PromotionStatistics";
			public const string PromotionsPrizeAwarding = "PromotionsPrizeAwarding";
			public const string ManagePromotionGroups = "ManagePromotionGroups";
			public const string ManagePromotions = "ManagePromotions";
			public const string LossAchievementPromotions = "LossAchievementPromotions";
			public const string OptInOnlyPromotions = "OptInOnlyPromotions";
			public const string RoundAchievementPromotions = "RoundAchievementPromotions";
			public const string SingleBetAchievementPromotions = "SingleBetAchievementPromotions";
			public const string SingleWinAchievementPromotions = "SingleWinAchievementPromotions";
			public const string WinAchievementPromotions = "WinAchievementPromotions";
			public const string BetAchievementPromotions = "BetAchievementPromotions";
			public const string ManageCoupons = "ManageCoupons";
			public const string VoucherManagement = "VoucherManagement";
			public const string BonusCustomTypes = "BonusCustomTypes";
			public const string BonusStatistics = "BonusStatistics";
			public const string BulkManualBonus = "BulkManualBonus";
			public const string ManageBonusGroups = "ManageBonusGroups";
			public const string ManageBonuses = "ManageBonuses";
			public const string ManageFreeRoundProfiles = "ManageFreeRoundProfiles";
			public const string SportsbookCashback = "SportsbookCashback";
			public const string BonusCommonFunctionality = "BonusCommonFunctionality";
			public const string DepositBonus = "DepositBonus";
			public const string DirectGiveBonus = "DirectGiveBonus";
			public const string LoginBonus = "LoginBonus";
			public const string ManualBonus = "ManualBonus";
			public const string ThirdPartyFreeRoundsBonus = "ThirdPartyFreeRoundsBonus";
			public const string TriggerBonus = "TriggerBonus";
		}

		public static class Reports 
		{
 			public const string ManageCustomReports = "ManageCustomReports";
			public const string ManageReportsVisibility = "ManageReportsVisibility";
			public const string NewReport = "NewReport";
			public const string ReportSubscription = "ReportSubscription";
			public const string ManageAllReportGroups = "ManageAllReportGroups";
			public const string ViewAllReportGroups = "ViewAllReportGroups";
			public const string ViewAllReports = "ViewAllReports";
			public const string OwnerAccountingStatsReport = "OwnerAccountingStatsReport";
			public const string PlayerStatisticsReport = "PlayerStatisticsReport";
			public const string ProfitabilityReport = "ProfitabilityReport";
		}

		public static class Players 
		{
 			public const string AddDeviceAccount = "AddDeviceAccount";
			public const string DeviceAdvancedSearch = "DeviceAdvancedSearch";
			public const string DeviceSearch = "DeviceSearch";
			public const string PlayerGroups = "PlayerGroups";
			public const string PlayerSelection = "PlayerSelection";
			public const string PlayerVIPLevels = "PlayerVIPLevels";
			public const string ManualPlayerRegistry = "ManualPlayerRegistry";
			public const string OnlinePlayers = "OnlinePlayers";
			public const string PlayerAdvancedSearch = "PlayerAdvancedSearch";
			public const string PlayerControl = "PlayerControl";
			public const string PlayerLobby = "PlayerLobby";
			public const string PlayerStatusManagement = "PlayerStatusManagement";
			public const string SearchPlayer = "SearchPlayer";
			public const string SelfRestrictedPlayers = "SelfRestrictedPlayers";
			public const string ExternalDepositsWithdrawals = "ExternalDepositsWithdrawals";
			public const string ManagePlayerAccounts = "ManagePlayerAccounts";
			public const string PlayerAuditTrail = "PlayerAuditTrail";
			public const string PlayerBonusesPromotions = "PlayerBonusesPromotions";
			public const string PlayerCardsinPlayerAccount = "PlayerCardsinPlayerAccount";
			public const string PlayerChargebacks = "PlayerChargebacks";
			public const string PlayerCommunication = "PlayerCommunication";
			public const string PlayerDepositAuthorization = "PlayerDepositAuthorization";
			public const string PlayerDeviceAccountsinPlayerAccount = "PlayerDeviceAccountsinPlayerAccount";
			public const string PlayerFraudManagement = "PlayerFraudManagement";
			public const string PlayerGameActivity = "PlayerGameActivity";
			public const string PlayerInfo = "PlayerInfo";
			public const string PlayerKYC = "PlayerKYC";
			public const string PlayerLoyalty = "PlayerLoyalty";
			public const string PlayerManualGameBet = "PlayerManualGameBet";
			public const string PlayerPlayLimits = "PlayerPlayLimits";
			public const string PlayerPreferences = "PlayerPreferences";
			public const string PlayerRecommendations = "PlayerRecommendations";
			public const string PlayerRestrictions = "PlayerRestrictions";
			public const string PlayerSegmentsforPlayer = "PlayerSegmentsforPlayer";
			public const string PlayerSessionManagement = "PlayerSessionManagement";
		}

		public static class Users 
		{
 			public const string ManageCurrentUser = "ManageCurrentUser";
			public const string ManageUserGroups = "ManageUserGroups";
			public const string ManageUsers = "ManageUsers";
			public const string AllUsersLogs = "AllUsersLogs";
			public const string ManagePageLogsType = "ManagePageLogsType";
		}

		public static class Communication 
		{
 			public const string ManageTemplate = "ManageTemplate";
			public const string Greetings = "Greetings";
			public const string Messages = "Messages";
		}

		public static class RuleEngine 
		{
 			public const string ManageRules = "ManageRules";
			public const string Recommendations = "Recommendations";
			public const string AddPushNotifications = "AddPushNotifications";
			public const string ManagePushNotifications = "ManagePushNotifications";
			public const string CustomPrizes = "CustomPrizes";
			public const string LoyaltyBadges = "LoyaltyBadges";
			public const string LoyaltyPoints = "LoyaltyPoints";
			public const string RedemptionSchemes = "RedemptionSchemes";
		}

		public static class System 
		{
 			public const string ManageExperiencePages = "ManageExperiencePages";
			public const string ManageExperienceVideos = "ManageExperienceVideos";
			public const string ManagePageVideos = "ManagePageVideos";
			public const string InternalPageManagement = "InternalPageManagement";
			public const string MethodManagement = "MethodManagement";
			public const string PageManagement = "PageManagement";
			public const string PageReportsManagement = "PageReportsManagement";
			public const string RibbonManagement = "RibbonManagement";
			public const string LogsManagement = "LogsManagement";
			public const string SimpleView = "SimpleView";
			public const string SystemRegexValidation = "SystemRegexValidation";
			public const string SystemSettings = "SystemSettings";
			public const string SimulationEngineStatistics = "SimulationEngineStatistics";
			public const string ContextManagement = "ContextManagement";
			public const string LanguageTranslations = "LanguageTranslations";
			public const string ReferenceManagement = "ReferenceManagement";
			public const string ManageJobs = "ManageJobs";
			public const string WidgetsandCategories = "WidgetsandCategories";
			public const string ManageConnections = "ManageConnections";
		}


	} 
}