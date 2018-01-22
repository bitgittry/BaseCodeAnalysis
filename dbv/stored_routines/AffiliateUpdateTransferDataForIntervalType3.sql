DROP procedure IF EXISTS `AffiliateUpdateTransferDataForIntervalType3`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AffiliateUpdateTransferDataForIntervalType3`(queryDateIntervalID BIGINT, OUT statusCode INT)
root:BEGIN
  
  -- This was a failover which probably we don't need any more 
/*
  UPDATE gaming_clients FORCE INDEX (sign_up_date)
  STRAIGHT_JOIN gaming_affiliates ON 
	external_id = SUBSTRING(affiliate_registration_code FROM 1 FOR LOCATE('_',affiliate_registration_code) -1)
  SET gaming_clients.affiliate_id = gaming_affiliates.affiliate_id
  WHERE gaming_clients.sign_up_date > DATE_ADD(NOW(),INTERVAL -5 DAY) AND affiliate_registration_code IS NOT NULL AND
	gaming_clients.affiliate_id IS NULL AND LOCATE('_',affiliate_registration_code)!= 0;
*/

  SET @queryDateIntervalID=-1;
 SELECT query_date_interval_id, date_from, date_to
    INTO @queryDateIntervalID, @dateFrom, @dateTo
    FROM gaming_query_date_intervals WHERE query_date_interval_id=queryDateIntervalID;

  IF (@queryDateIntervalIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT lock_id INTO @lockID FROM gaming_locks WHERE name='affiliate_update_transfer_data' FOR UPDATE;

  DELETE FROM gaming_affiliate_client_transfers WHERE query_date_interval_id=@queryDateIntervalID;
  INSERT INTO gaming_affiliate_client_transfers (affiliate_system_id, query_date_interval_id, actual_client_id, client_id, 
	country_code, banner_tag, affiliate_id, registration_ip, registration_date, username)
  SELECT gaming_affiliate_systems.affiliate_system_id, @queryDateIntervalID, gaming_clients.client_id,
	IF(gaming_affiliate_systems.use_external_client_id AND gaming_clients.ext_client_id IS NOT NULL, 
		gaming_clients.ext_client_id, gaming_clients.client_id+IFNULL(gaming_affiliate_systems.prefix_client_id,0)) AS client_id,
	gaming_countries.country_code, gaming_clients.affiliate_registration_code, gaming_clients.affiliate_id, 
    IFNULL(gaming_clients.registration_ipaddress_v4,'127.0.0.1'), gaming_clients.sign_up_date, IFNULL(gaming_clients.username, gaming_clients.client_id)
  FROM gaming_client_registrations FORCE INDEX (registration_type_created_date)
  STRAIGHT_JOIN gaming_clients ON 
	gaming_clients.client_id=gaming_client_registrations.client_id
  STRAIGHT_JOIN gaming_affiliates ON 
	gaming_affiliates.affiliate_id=gaming_clients.affiliate_id AND 
    gaming_affiliates.is_active=1
  STRAIGHT_JOIN gaming_affiliate_systems ON 
	gaming_affiliate_systems.affiliate_system_id=gaming_affiliates.affiliate_system_id AND 
    gaming_affiliate_systems.is_active=1
  STRAIGHT_JOIN clients_locations ON 
	gaming_clients.client_id=clients_locations.client_id AND 
    clients_locations.is_primary=1
  STRAIGHT_JOIN gaming_countries ON 
	clients_locations.country_id=gaming_countries.country_id
  STRAIGHT_JOIN gaming_client_stats ON 
	gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
  LEFT JOIN gaming_affiliate_client_transfers FORCE INDEX (actual_client_id) ON
	gaming_affiliate_client_transfers.actual_client_id=gaming_clients.client_id
  WHERE
    (gaming_client_registrations.client_registration_type_id=3 AND -- Fully Registered
	 gaming_client_registrations.created_date BETWEEN @dateFrom AND @dateTo) AND
    gaming_client_registrations.is_current=1 AND gaming_affiliate_client_transfers.actual_client_id IS NULL;
  
  SELECT gaming_operators.currency_id INTO @operatorCurrencyID 
  FROM gaming_operators 
  JOIN gaming_currency ON gaming_operators.currency_id=gaming_currency.currency_id 
  WHERE gaming_operators.is_main_operator=1;
  
  SET @productRef=1;

  DELETE FROM gaming_affiliate_client_activity_transfers WHERE query_date_interval_id=@queryDateIntervalID;
  INSERT INTO gaming_affiliate_client_activity_transfers(
		affiliate_system_id, query_date_interval_id, actual_client_id,
	   client_id, activity_date, product_ref,
	   gross_revenue, bet, win,
	   jackpot_contribution, bonuses, adjustments,
	   chargebacks, turnover, deposits,
	   withdrawals, currency_id, casino_gross_revenue,
	   casino_turnover, poker_gross_revenue, poker_turnover,
	   sports_gross_revenue, sports_turnover,
	   poolbetting_gross_revenue, poolbetting_turnover,
	   casino_num_of_bets, sportbook_num_of_bets, poker_num_of_bets,
	   casino_bet_bonus, poker_bet_bonus, sports_bet_bonus, 
	   casino_win_bonus, poker_win_bonus, sports_win_bonus,
	   bonus_given_base) 
  SELECT gaming_affiliate_systems.affiliate_system_id
         , @queryDateIntervalID
         , gaming_clients.client_id
         , IF(gaming_affiliate_systems.use_external_client_id AND gaming_clients.ext_client_id IS NOT NULL, 
			gaming_clients.ext_client_id, gaming_clients.client_id + IFNULL(gaming_affiliate_systems.prefix_client_id, 0)) AS client_id
         , @dateFrom,
         @productRef,
         ROUND((IFNULL(Rounds.Bet - Rounds.Win - IFNULL(Transactions.SBAdjustments,0), 0) + IFNULL(ggmps.gross_revenue_base, 0)) / 100, 2) AS gross_revenue,
         ROUND(IFNULL(Rounds.Bet, 0) / 100, 2) AS bet,
         ROUND(IFNULL(Rounds.Win + IFNULL(Transactions.SBAdjustments,0), 0) / 100, 2) AS win,
         0 AS jackpot_contribution,
         ROUND(IFNULL(Transactions.Bonuses, 0) / 100, 2) AS bonuses,
         ROUND(IFNULL(Transactions.Adjustments, 0) / 100, 2) AS adjustments,
         ROUND(IFNULL(Transactions.Cashback, 0) / 100, 2) AS chargebacks,
         ROUND(IFNULL(Rounds.Bet, 0) / 100, 2) AS turnover,
         ROUND(IFNULL(Transactions.Deposits, 0) / 100, 2) AS deposits,
         ROUND(IFNULL(Transactions.Withdrawals, 0) / 100, 2) AS withdrawals,
         @operatorCurrencyID AS currency_id,
         ROUND(IFNULL(Rounds.CasinoBet - Rounds.CasinoWin, 0) / 100, 2) AS casino_gross_revenue,
         ROUND(IFNULL(Rounds.CasinoBet, 0) / 100, 2) AS casino_turnover,
         ROUND(IFNULL(Rounds.PokerBet - Rounds.PokerWin, 0) / 100, 2) AS poker_gross_revenue,
         ROUND(IFNULL(Rounds.PokerBet, 0) / 100, 2) AS poker_turnover,
         ROUND(IFNULL(Rounds.SportsBet - Rounds.SportsWin - IFNULL(Transactions.SBAdjustments,0), 0) / 100, 2) AS sports_gross_revenue,
         ROUND(IFNULL(Rounds.SportsBet, 0) / 100, 2) AS sports_turnover,
         ROUND(IFNULL(OpComm.Commissions, 0) / 100, 2) AS poolbetting_gross_revenue, 
         ROUND(IFNULL(OpComm.PoolBet, 0) / 100, 2) AS poolbetting_turnover, 
         CasinoBetCount, SportBetCount, PokerHandsCount,
		 ROUND(IFNULL(Rounds.CasinoBetBonus, 0) / 100, 2) AS CasinoBetBonus,
		 ROUND(IFNULL(Rounds.PokerBetBonus, 0) / 100, 2) AS PokerBetBonus,
		 ROUND(IFNULL(Rounds.SportsBetBonus, 0) / 100, 2) AS SportsBetBonus,
		 ROUND(IFNULL(Rounds.CasinoWinBonus, 0) / 100, 2) AS CasinoWinBonus,
		 ROUND(IFNULL(Rounds.PokerWinBonus, 0) / 100, 2) AS PokerWinBonus,
		 ROUND(IFNULL(Rounds.SportsWinBonus, 0) / 100, 2) AS SportsWinBonus,
		 ROUND(IFNULL(Transactions.BonusAwarded, 0) / 100, 2) AS BonusAwarded
	     -- 555 AS BonusAwarded
	FROM gaming_client_stats FORCE INDEX (balance_last_change_date)
    STRAIGHT_JOIN gaming_clients ON  
		gaming_clients.client_id=gaming_client_stats.client_id AND gaming_clients.affiliate_id IS NOT NULL
	STRAIGHT_JOIN gaming_affiliates ON 
		gaming_clients.affiliate_id = gaming_affiliates.affiliate_id AND 
		gaming_affiliates.is_active = 1
	STRAIGHT_JOIN gaming_affiliate_systems ON 
		gaming_affiliate_systems.is_active = 1 AND 
		gaming_affiliate_systems.affiliate_system_id = gaming_affiliates.affiliate_system_id
	LEFT JOIN 
	(
		SELECT   player_rounds.client_id,
				 SUM(bet_real) AS 'Bet',
				 SUM(win_real) AS 'Win',
				 0 AS 'JackpotContributions',
				 SUM(IF(license_type_id = 1, bet_real, 0)) AS 'CasinoBet',
				 SUM(IF(license_type_id = 1, win_real, 0)) AS 'CasinoWin',
				 SUM(IF(license_type_id = 1, bet_bonus, 0)) AS 'CasinoBetBonus',
				 SUM(IF(license_type_id = 1, win_bonus, 0)) AS 'CasinoWinBonus',
				 SUM(IF(license_type_id = 1, num_of_rounds, 0)) AS 'CasinoBetCount',
				 SUM(IF(license_type_id = 2, bet_real, 0)) AS 'PokerBet',
				 SUM(IF(license_type_id = 2, win_real, 0)) AS 'PokerWin',
				 SUM(IF(license_type_id = 2, bet_bonus, 0)) AS 'PokerBetBonus',
				 SUM(IF(license_type_id = 2, win_bonus, 0)) AS 'PokerWinBonus',
				 SUM(IF(license_type_id = 2, num_of_rounds, 0)) AS 'PokerHandsCount',
				 SUM(IF(license_type_id = 3, bet_real, 0)) AS 'SportsBet',
				 SUM(IF(license_type_id = 3, win_real, 0)) AS 'SportsWin',
				 SUM(IF(license_type_id = 3, bet_bonus, 0)) AS 'SportsBetBonus',
				 SUM(IF(license_type_id = 3, win_bonus, 0)) AS 'SportsWinBonus',
				 SUM(IF(license_type_id = 3, num_of_rounds, 0)) AS 'SportBetCount'
				 
		FROM     gaming_game_transactions_aggregation_player_rounds AS player_rounds FORCE INDEX (date_from)
		WHERE    player_rounds.date_from BETWEEN @dateFrom AND @dateTo
		GROUP BY player_rounds.client_id
	) AS Rounds ON gaming_clients.client_id = Rounds.client_id

	LEFT JOIN 
    (
		SELECT   player_license.client_id,
				 SUM(bet_real) AS 'PoolBet',
				 SUM(win_real) AS 'PoolWin',
				 SUM(operator_commission) AS 'Commissions'
		FROM     gaming_game_transactions_aggregation_licence_player AS player_license FORCE INDEX (date_from)
		WHERE    player_license.date_from BETWEEN @dateFrom AND @dateTo
				 AND player_license.licence_type_id = 5
		GROUP BY player_license.client_id
	) AS OpComm ON gaming_clients.client_id = OpComm.client_id           
         
	LEFT JOIN gaming_game_manufacturers_player_stats ggmps ON gaming_clients.client_id = ggmps.client_id AND 
		ggmps.license_type_id = 2 AND ggmps.date BETWEEN @dateFrom AND @dateTo
	LEFT JOIN
	(
		SELECT   gaming_transactions.client_id
			   , ROUND(IFNULL(SUM(IF(AdjustmentsTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Adjustments'
			   , ROUND(IFNULL(SUM(IF(CashbackTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Cashback'
			   , ROUND(IFNULL(SUM(IF(BonusRequirementMetTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Bonuses'
			   , ROUND(IFNULL(SUM(IF(DepositTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Deposits'
			   , ROUND(IFNULL(SUM(IF(WithdrawalTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Withdrawals'
			   , ROUND(IFNULL(SUM(IF(SBTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'SBAdjustments'
				, ROUND(IFNULL(SUM(IF(BonusAwardedTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'BonusAwarded'
		FROM  gaming_transactions USE INDEX ( timestamp )
			   JOIN gaming_payment_transaction_type AS AllTransactionTypes
				 ON (AllTransactionTypes.name IN ('Cashback', 'Compensation', 'Winnings',
					'Correction', 'TournamentWin', 'BonusRequirementMet',
					'Deposit', 'DepositCancelled', 'Withdrawal',
					'WithdrawalRequest', 'WithdrawalCancelled', 'CreditCardDepositAdjustment',
					'NetellerDepositAdjustment', 'SkrillDepositAdjustment', 'InstaDebitDepositAdjustment',
					'EcoCardDepositAdjustment', 'UkashDepositAdjustment', 'CepbankDepositAdjustment',
					'CreditCardWithdrawalAdjustment', 'NetellerWithdrawalAdjustment', 'SkrillWithdrawalAdjustment',
					'InstaDebitWithdrawalAdjustment', 'EcoCardWithdrawalAdjustment', 'UkashWithdrawalAdjustment',
					'CepbankWithdrawalAdjustment','SBWinnings','CashBonus','RedeemBonus','BonusTurnedReal','BonusCashExchange','BonusAwarded') OR AllTransactionTypes.is_affiliate_compensation_type) AND
					AllTransactionTypes.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			   LEFT JOIN gaming_payment_transaction_type AS AdjustmentsTransactions
				 ON AllTransactionTypes.is_affiliate_compensation_type AND AdjustmentsTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			   LEFT JOIN gaming_payment_transaction_type AS CashbackTransactions
				 ON CashbackTransactions.name IN ('Cashback') AND CashbackTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			  LEFT JOIN gaming_payment_transaction_type AS SBTransactions
				 ON SBTransactions.name IN ('SBWinnings') AND SBTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			   LEFT JOIN gaming_payment_transaction_type AS BonusRequirementMetTransactions
				 ON BonusRequirementMetTransactions.name IN ('BonusRequirementMet') AND BonusRequirementMetTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
				LEFT JOIN gaming_payment_transaction_type AS BonusAwardedTransactions
				 ON BonusAwardedTransactions.name IN ('BonusAwarded') AND BonusAwardedTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			   LEFT JOIN gaming_payment_transaction_type AS DepositTransactions
				 ON DepositTransactions.name IN ('Deposit', 'DepositCancelled', 'CreditCardDepositAdjustment',
					'NetellerDepositAdjustment', 'SkrillDepositAdjustment', 'InstaDebitDepositAdjustment',
					'EcoCardDepositAdjustment', 'UkashDepositAdjustment', 'CepbankDepositAdjustment') AND DepositTransactions.
					payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
			   LEFT JOIN gaming_payment_transaction_type AS WithdrawalTransactions
				 ON WithdrawalTransactions.name IN ('Withdrawal', 'WithdrawalRequest', 'WithdrawalCancelled',
					'CreditCardWithdrawalAdjustment', 'NetellerWithdrawalAdjustment', 'SkrillWithdrawalAdjustment',
					'InstaDebitWithdrawalAdjustment', 'EcoCardWithdrawalAdjustment', 'UkashWithdrawalAdjustment',
					'CepbankWithdrawalAdjustment') AND gaming_transactions.payment_transaction_type_id =
					  WithdrawalTransactions.payment_transaction_type_id
	  WHERE    gaming_transactions.timestamp BETWEEN @dateFrom AND @dateTo
	  GROUP BY gaming_transactions.client_id
	) AS Transactions ON gaming_clients.client_id = Transactions.client_id
  WHERE gaming_client_stats.balance_last_change_date > @dateFrom AND 
	(Rounds.client_id IS NOT NULL OR Transactions.client_id IS NOT NULL OR ggmps.client_id IS NOT NULL AND OpComm.client_id IS NOT NULL);


	UPDATE gaming_affiliate_client_activity_transfers FORCE INDEX (query_date_interval_id)
	LEFT JOIN gaming_game_manufacturers_player_stats ggmps ON 
		gaming_affiliate_client_activity_transfers.client_id = ggmps.client_id AND 
        ggmps.license_type_id = 2 AND ggmps.date BETWEEN @dateFrom AND @dateTo
	SET sports_chargebacks = IFNULL(ROUND((sports_turnover / turnover) * chargebacks, 2), 0),
		sports_adjustments = IFNULL(ROUND((sports_turnover / turnover) * adjustments, 2), 0),
		sports_bonuses = IFNULL(ROUND((sports_turnover / (turnover - poker_turnover)) * bonuses, 2), 0),
        
		casino_chargebacks = IFNULL(ROUND((casino_turnover / turnover) * chargebacks, 2), 0),
		casino_adjustments = IFNULL(ROUND((casino_turnover / turnover) * adjustments, 2), 0),
		casino_bonuses = IFNULL(ROUND((casino_turnover / (turnover - poker_turnover)) * bonuses, 2), casino_bonuses),
        
		poker_chargebacks = IFNULL(ROUND((poker_turnover / turnover) * chargebacks, 2), 0),
		poker_adjustments = IFNULL(ROUND((poker_turnover / turnover) * adjustments, 2), 0),
		poker_bonuses = IFNULL(ROUND((gross_revenue_base - net_gross_revenue_base) / 100, 2), 0),
        
		poolbetting_chargebacks = IFNULL(ROUND((poolbetting_turnover / turnover) * chargebacks, 2), 0),  
		poolbetting_adjustments = IFNULL(ROUND((poolbetting_turnover / turnover) * adjustments, 2), 0),  
		poolbetting_bonuses = IFNULL(ROUND((poolbetting_turnover / (turnover - poker_turnover)) * bonuses, 2), 0)  
	WHERE query_date_interval_id = @queryDateIntervalID AND turnover != 0;
  
  
	-- if the player has never placed a bet, both the turnover and the total_real_wagered are zero
	-- in this edge case we decide to pass all the chargebacks and adjustments to one of the licenses (the first one active) without splitting it
  SELECT `name` FROM gaming_settings 
  WHERE `name` IN ('CASINO_ACTIVE','POKER_ACTIVE','SPORTSBOOK_ACTIVE','POOL_BETTING_ACTIVE') AND value_bool=1 ORDER BY setting_id 
  LIMIT 1
  INTO @main_license;

  UPDATE 
  (
	  SELECT  client_id, 
			IF(total_wagered=0,1,total_wagered) as total_wagered, 
			IF(IFNULL(@main_license,'CASINO_ACTIVE')='CASINO_ACTIVE',IF(total_wagered=0,1,casino_wagered),casino_wagered) as casino_wagered,
			IF(IFNULL(@main_license,'CASINO_ACTIVE')='POKER_ACTIVE',IF(total_wagered=0,1,poker_wagered),poker_wagered) as poker_wagered,
			IF(IFNULL(@main_license,'CASINO_ACTIVE')='SPORTSBOOK_ACTIVE',IF(total_wagered=0,1,sports_wagered),sports_wagered) as sports_wagered,
			IF(IFNULL(@main_license,'CASINO_ACTIVE')='POOL_BETTING_ACTIVE',IF(total_wagered=0,1,pool_wagered),pool_wagered) as pool_wagered
	  FROM 
	  (
			SELECT client_activity.client_id, SUM(gaming_client_wager_stats.total_real_wagered) AS total_wagered,
			  SUM(IF(gaming_client_wager_types.license_type_id=1, gaming_client_wager_stats.total_real_wagered, 0)) AS casino_wagered,
			  SUM(IF(gaming_client_wager_types.license_type_id=2, gaming_client_wager_stats.total_real_wagered, 0)) AS poker_wagered,
			  SUM(IF(gaming_client_wager_types.license_type_id=3, gaming_client_wager_stats.total_real_wagered, 0)) AS sports_wagered,
			  SUM(IF(gaming_client_wager_types.license_type_id=5, gaming_client_wager_stats.total_real_wagered, 0)) AS pool_wagered  
			FROM gaming_affiliate_client_activity_transfers AS client_activity FORCE INDEX (query_date_interval_id)
			STRAIGHT_JOIN gaming_client_stats ON client_activity.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
			STRAIGHT_JOIN gaming_client_wager_stats ON gaming_client_stats.client_stat_id=gaming_client_wager_stats.client_stat_id
			STRAIGHT_JOIN gaming_client_wager_types ON gaming_client_wager_stats.client_wager_type_id=gaming_client_wager_types.client_wager_type_id
			WHERE client_activity.query_date_interval_id=@queryDateIntervalID AND client_activity.turnover=0
			GROUP BY client_activity.client_id 
	  ) as dvtbl
  ) AS Wagered 
  STRAIGHT_JOIN gaming_affiliate_client_activity_transfers AS client_activity FORCE INDEX (query_date_interval_id) ON 
	client_activity.query_date_interval_id=@queryDateIntervalID AND client_activity.turnover=0 AND
	client_activity.client_id=Wagered.client_id
  LEFT JOIN gaming_game_manufacturers_player_stats ggmps ON client_activity.client_id = ggmps.client_id AND 
	ggmps.license_type_id=2 AND ggmps.date BETWEEN @dateFrom AND @dateTo
  SET 
	sports_chargebacks=IFNULL(ROUND((sports_wagered/total_wagered)*chargebacks,2),0),
	sports_adjustments=IFNULL(ROUND((sports_wagered/total_wagered)*adjustments,2),0),
	sports_bonuses=IFNULL(ROUND((sports_wagered/(total_wagered-poker_wagered))*bonuses,2),0),
    
	casino_chargebacks=IFNULL(ROUND((casino_wagered/total_wagered)*chargebacks,2),0),
	casino_adjustments=IFNULL(ROUND((casino_wagered/total_wagered)*adjustments,2),0),
	casino_bonuses=IFNULL(ROUND((casino_wagered/(total_wagered-poker_wagered))*bonuses,2),0),
    
	poker_chargebacks=IFNULL(ROUND((poker_wagered/total_wagered)*chargebacks,2),0),
	poker_adjustments=IFNULL(ROUND((poker_wagered/total_wagered)*adjustments,2),0),
    
	poker_bonuses=IFNULL(ROUND((gross_revenue_base-net_gross_revenue_base)/100,2),0),  
	poolbetting_chargebacks=IFNULL(ROUND((pool_wagered/total_wagered)*chargebacks,2),0),  
	poolbetting_adjustments=IFNULL(ROUND((pool_wagered/total_wagered)*adjustments,2),0),  
	poolbetting_bonuses=IFNULL(ROUND((pool_wagered/(total_wagered-poker_wagered))*bonuses,2),0);
  
  
  SET statusCode=0;

END root$$

DELIMITER ;

