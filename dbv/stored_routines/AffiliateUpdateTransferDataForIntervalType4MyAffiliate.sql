DROP procedure IF EXISTS `AffiliateUpdateTransferDataForIntervalType4MyAffiliate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AffiliateUpdateTransferDataForIntervalType4MyAffiliate`(queryDateIntervalID BIGINT, OUT statusCode INT)
root:BEGIN

   /* Status Codes
   * 0 - Sucess
   * 1 - Date Interval not found
   * 2 - Interval is in the future or not ended yet
  */


/*
  UPDATE gaming_clients 
  JOIN gaming_affiliates ON external_id = SUBSTRING(affiliate_registration_code FROM  1 FOR LOCATE('_',affiliate_registration_code) -1)
  SET gaming_clients.affiliate_id = gaming_affiliates.affiliate_id
  WHERE gaming_clients.sign_up_date > DATE_ADD(NOW(),INTERVAL -5 DAY) AND affiliate_registration_code IS NOT NULL AND 
	gaming_clients.affiliate_id IS NULL AND LOCATE('_',affiliate_registration_code)!= 0;
*/

  SET @queryDateIntervalID=-1;
  SELECT gaming_query_date_intervals.query_date_interval_id, gaming_query_date_intervals.date_from, gaming_query_date_intervals.date_to
  INTO @queryDateIntervalID, @dateFrom, @dateTo
  FROM gaming_query_date_interval_types
  JOIN gaming_query_date_intervals ON
    gaming_query_date_intervals.query_date_interval_id=queryDateIntervalID AND 
    gaming_query_date_interval_types.query_date_interval_type_id=gaming_query_date_intervals.query_date_interval_type_id
  WHERE query_date_interval_id=queryDateIntervalID;

  IF (@queryDateIntervalIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  -- Get Lock ensuring only one connection is executing at a time.
  SELECT lock_id INTO @lockID FROM gaming_locks WHERE name='affiliate_update_transfer_data' FOR UPDATE;

  -- Insert into affiliate stats tables (Affiliate needs to be active)

  -- 1. Client Transfer
  DELETE FROM gaming_affiliate_client_transfers WHERE query_date_interval_id=@queryDateIntervalID;
  INSERT INTO gaming_affiliate_client_transfers (affiliate_system_id, query_date_interval_id, actual_client_id, client_id, country_code, banner_tag, affiliate_id, registration_ip, registration_date, username, currency_code)
  SELECT gaming_affiliate_systems.affiliate_system_id, @queryDateIntervalID, gaming_clients.client_id,
 IF(gaming_affiliate_systems.use_external_client_id AND gaming_clients.ext_client_id IS NOT NULL, gaming_clients.ext_client_id, gaming_clients.client_id+IFNULL(gaming_affiliate_systems.prefix_client_id,0)) AS client_id,
 gaming_countries.country_code, gaming_clients.affiliate_registration_code, gaming_clients.affiliate_id, IFNULL(gaming_clients.registration_ipaddress_v4,'127.0.0.1'), gaming_clients.sign_up_date, gaming_clients.username,
 gaming_currency.currency_code
  FROM gaming_affiliates
  JOIN gaming_affiliate_systems ON  gaming_affiliate_systems.is_active=1 AND gaming_affiliate_systems.affiliate_system_id=gaming_affiliates.affiliate_system_id
  JOIN gaming_clients ON
    gaming_affiliates.affiliate_id=gaming_clients.affiliate_id AND
    (gaming_clients.sign_up_date BETWEEN @dateFrom AND @dateTo) AND gaming_clients.is_test_player=0
  JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1
  JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
  JOIN gaming_client_stats ON gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
  JOIN gaming_currency ON gaming_client_stats.currency_id = gaming_currency.currency_id
  WHERE gaming_affiliates.is_active=1;


  -- 2. Client Activity Transfer

  SELECT gaming_operators.currency_id INTO @operatorCurrencyID FROM gaming_operators JOIN gaming_currency ON gaming_operators.currency_id=gaming_currency.currency_id WHERE gaming_operators.is_main_operator=1;
  SET @productRef=1;

  DELETE FROM gaming_affiliate_client_activity_transfers WHERE query_date_interval_id=@queryDateIntervalID;
  INSERT INTO gaming_affiliate_client_activity_transfers(affiliate_system_id, query_date_interval_id, actual_client_id, client_id, activity_date, product_ref, gross_revenue,
    bet, win, jackpot_contribution, bonuses, adjustments, chargebacks, turnover, deposits, withdrawals, currency_id,
    casino_gross_revenue, casino_turnover, poker_gross_revenue, poker_turnover, sports_gross_revenue, sports_turnover, loyalty_points,
    -- Additional data in feeds
    bonus_given_base, bonus_turned_real_base,
    bonus_bets_base, bonus_wins_base, amount_expired_base, amount_cancelled_base, free_round_awarded,
    free_round_lost, free_round_turned_bonus, free_round_turned_real,
    casino_bet_bonus, casino_win_bonus, poker_bet_bonus, poker_win_bonus, sports_bet_bonus, sports_win_bonus)
    SELECT   gaming_affiliate_systems.affiliate_system_id
             , @queryDateIntervalID
             , gaming_clients.client_id actual_client_id
             , IF(gaming_affiliate_systems.use_external_client_id AND gaming_clients.ext_client_id IS NOT NULL, gaming_clients.ext_client_id, gaming_clients.client_id + IFNULL(gaming_affiliate_systems.prefix_client_id, 0)) AS client_id
             , @dateFrom,
             @productRef,
             ROUND((IFNULL(Rounds.Bet - Rounds.Win, 0) + IFNULL(ggmps.gross_revenue_base, 0)) / 100, 2) AS gross_revenue,
             ROUND(IFNULL(Rounds.Bet, 0) / 100, 2) AS bet,
             ROUND(IFNULL(Rounds.Win, 0) / 100, 2) AS win,
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
             ROUND((IFNULL(Rounds.PokerBet - Rounds.PokerWin, 0) + IFNULL(ggmps.gross_revenue, 0)) / 100, 2) AS poker_gross_revenue,
             ROUND(IFNULL(Rounds.PokerBet, 0) / 100, 2) AS poker_turnover,
             ROUND(IFNULL(Rounds.SportsBet - Rounds.SportsWin, 0) / 100, 2) AS sports_gross_revenue,
             ROUND(IFNULL(Rounds.SportsBet, 0) / 100, 2) AS sports_turnover,
             ROUND(SUM(IFNULL((ggtapg.loyalty_points), 0)), 2),
             ROUND(IFNULL(BonusesGiven, 0) / 100, 2) AS BonusesGiven,
             ROUND(IFNULL(BonusesTurnedReal, 0) / 100, 2) AS BonusesTurnedReal,
             ROUND(IFNULL(BetBonus, 0) / 100, 2) AS BetBonus,
             ROUND(IFNULL(WinBonus, 0) / 100, 2) AS WinBonus,
             ROUND(IFNULL(ExpiredAmounts, 0) / 100, 2) AS ExpiredAmounts,
             ROUND(IFNULL(CancelledAmounts, 0) / 100, 2) AS CancelledAmounts,
             ROUND(IFNULL(FreeRoundAwarded, 0) / 100, 2) AS FreeRoundAwarded,
             ROUND(IFNULL(FreeRoundsLost, 0) / 100, 2) AS FreeRoundsLost,
             ROUND(IFNULL(FreeRoundsTurnedToBonus, 0) / 100, 2) AS FreeRoundsTurnedToBonus,
             ROUND(IFNULL(FreeRoundsTurnedToReal, 0) / 100, 2) AS FreeRoundsTurnedToReal,
             ROUND(IFNULL(CasinoBetBonus, 0) / 100, 2) AS CasinoBetBonus,
             ROUND(IFNULL(CasinoWinBonus, 0) / 100, 2) AS CasinoWinBonus,
             ROUND(IFNULL(PokerBetBonus, 0) / 100, 2) AS PokerBetBonus,
             ROUND(IFNULL(PokerWinBonus, 0) / 100, 2) AS PokerWinBonus,
             ROUND(IFNULL(SportsBetBonus, 0) / 100, 2) AS SportsBetBonus,
             ROUND(IFNULL(SportsWinBonus, 0) / 100, 2) AS SportsWinBonus
    FROM     gaming_clients
             JOIN gaming_affiliates
               ON gaming_clients.affiliate_id = gaming_affiliates.affiliate_id AND gaming_clients.is_test_player = 0 AND
                  gaming_affiliates.is_active = 1
             JOIN gaming_affiliate_systems
               ON gaming_affiliate_systems.is_active = 1 AND gaming_affiliate_systems.affiliate_system_id =
                    gaming_affiliates.affiliate_system_id
             JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id
             LEFT JOIN (SELECT   player_rounds.client_id,
                                 SUM(bet_real) AS 'Bet',
                                 SUM(win_real) AS 'Win',
                                 0 AS 'JackpotContributions',
                                 SUM(IF(license_type_id = 1, bet_real, 0)) AS 'CasinoBet',
                                 SUM(IF(license_type_id = 1, win_real, 0)) AS 'CasinoWin',
                                 0 AS 'PokerBet',
                                 0 AS 'PokerWin',
                                 SUM(IF(license_type_id = 3, bet_real, 0)) AS 'SportsBet',
                                 SUM(IF(license_type_id = 3, win_real, 0)) AS 'SportsWin',
                                 -- NEW
                                 SUM(bet_bonus) AS 'BetBonus',
                                 SUM(win_bonus) AS 'WinBonus',
                                 SUM(IF(license_type_id = 1, bet_bonus, 0)) AS 'CasinoBetBonus',
                                 SUM(IF(license_type_id = 1, win_bonus, 0)) AS 'CasinoWinBonus',
                                 0 AS 'PokerBetBonus',
                                 0 AS 'PokerWinBonus',
                                 SUM(IF(license_type_id = 3, bet_bonus, 0)) AS 'SportsBetBonus',
                                 SUM(IF(license_type_id = 3, win_bonus, 0)) AS 'SportsWinBonus'
                        FROM     gaming_game_transactions_aggregation_player_rounds AS player_rounds
                        WHERE    player_rounds.date_from BETWEEN @dateFrom AND @dateTo
                        GROUP BY player_rounds.client_id) AS Rounds
               ON gaming_clients.client_id = Rounds.client_id
             LEFT JOIN gaming_game_manufacturers_player_stats ggmps
               ON (gaming_clients.client_id = ggmps.client_id AND ggmps.license_type_id = 2 AND ggmps.date BETWEEN @dateFrom AND @dateTo)
             LEFT JOIN
             (SELECT   gaming_transactions.client_id
                       , ROUND(IFNULL(SUM(IF(AdjustmentsTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Adjustments'
                       , ROUND(IFNULL(SUM(IF(CashbackTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Cashback'
                       , ROUND(IFNULL(SUM(IF(BonusTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'BonusesTurnedReal'
                       , ROUND(IFNULL(SUM(IF(BonusGivenTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'BonusesGiven'
                       , ROUND(IFNULL(SUM(IF(BonusFreeRoundTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'FreeRoundAwarded'
                       , ROUND(IFNULL(SUM(IF(BonusTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)),0),5) AS 'Bonuses'
                       , ROUND(IFNULL(SUM(IF(DepositTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Deposits'
                       , ROUND(IFNULL(SUM(IF(WithdrawalTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base)), 0), 5) AS 'Withdrawals'
              FROM     gaming_transactions USE INDEX ( timestamp )
                       JOIN gaming_payment_transaction_type AS AllTransactionTypes
                         ON AllTransactionTypes.name IN ('Cashback', 'Compensation', 'Winnings', 'Correction', 'TournamentWin',
                            'BonusRequirementMet', 'Deposit', 'DepositCancelled', 'Withdrawal', 'WithdrawalRequest',
                            'WithdrawalCancelled', 'BonusAwarded', 'BonusTurnedReal', 'BonusCashExchange', 'RedeemBonus',
                            'CashBonus', 'FreeRoundBonusAwarded') AND AllTransactionTypes.payment_transaction_type_id =
                              gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS AdjustmentsTransactions
                         ON AdjustmentsTransactions.name IN ('Compensation', 'Winnings', 'Correction', 'TournamentWin') AND
                            AdjustmentsTransactions.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS CashbackTransactions
                         ON CashbackTransactions.name IN ('Cashback') AND CashbackTransactions.payment_transaction_type_id =
                              gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS BonusTransactions
                         ON BonusTransactions.name IN ('BonusRequirementMet', 'BonusTurnedReal', 'BonusCashExchange', 'RedeemBonus',
                            'CashBonus') AND BonusTransactions.payment_transaction_type_id =
                              gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS BonusGivenTransactions
                         ON BonusGivenTransactions.name IN ('BonusAwarded') AND BonusGivenTransactions.payment_transaction_type_id =
                              gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS BonusFreeRoundTransactions
                         ON BonusFreeRoundTransactions.name IN ('FreeRoundBonusAwarded') AND BonusFreeRoundTransactions.payment_transaction_type_id
                            = gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS DepositTransactions
                         ON DepositTransactions.name IN ('Deposit', 'DepositCancelled') AND DepositTransactions.payment_transaction_type_id
                            = gaming_transactions.payment_transaction_type_id
                       LEFT JOIN gaming_payment_transaction_type AS WithdrawalTransactions
                         ON WithdrawalTransactions.name IN ('Withdrawal', 'WithdrawalCancelled') AND
                            gaming_transactions.payment_transaction_type_id = WithdrawalTransactions.payment_transaction_type_id
              WHERE    gaming_transactions.timestamp BETWEEN @dateFrom AND @dateTo
              GROUP BY gaming_transactions.client_id) AS Transactions
               ON gaming_clients.client_id = Transactions.client_id
             LEFT JOIN gaming_game_transactions_aggregation_player_game ggtapg ON ggtapg.client_id = gaming_clients.client_id AND ggtapg.date_from BETWEEN @dateFrom AND @dateTo
             LEFT JOIN -- FREE ROUNDS
             (SELECT   client_id
                       , SUM(IF(gaming_payment_transaction_type.name = 'BonusAwarded', amount_total_base, 0)) AS 'FreeRoundsTurnedToBonus'
                       , SUM(IF(gaming_payment_transaction_type.name = 'BonusAwarded', 0, amount_total_base)) AS 'FreeRoundsTurnedToReal'
              FROM     gaming_transactions
                       JOIN gaming_payment_transaction_type
                         ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id
                       JOIN gaming_bonus_instances ON gaming_transactions.extra_id = gaming_bonus_instances.bonus_instance_id
              WHERE    gaming_payment_transaction_type.name IN ('BonusAwarded', 'BonusRequirementMet', 'BonusTurnedReal',
                       'BonusCashExchange', 'RedeemBonus', 'CashBonus') AND is_free_rounds = 1 AND gaming_transactions.timestamp BETWEEN @dateFrom AND @dateTo
              GROUP BY client_id) AS free_rounds_transactions
               ON free_rounds_transactions.client_id = gaming_clients.client_id
             LEFT JOIN -- FREE ROUNDS LOST
             (SELECT   gaming_bonus_losts.client_stat_id,
                       SUM(IF(name = 'Expired', gaming_bonus_losts.bonus_amount, 0)) AS ExpiredAmounts,
                       SUM(IF(name = 'Expired', 0, gaming_bonus_losts.bonus_amount)) AS CancelledAmounts,
                       SUM(IF(gaming_bonus_instances.is_free_rounds, gaming_bonus_losts.bonus_amount, 0)) AS FreeRoundsLost
              FROM     gaming_bonus_losts
                       JOIN gaming_bonus_instances ON gaming_bonus_instances.client_stat_id = gaming_bonus_losts.client_stat_id
                       JOIN gaming_bonus_lost_types ON gaming_bonus_losts.bonus_lost_type_id = gaming_bonus_lost_types.bonus_lost_type_id
              WHERE    name IN ('Expired', 'ForfeitByGameManufacturer', 'ForfeitByPlayer', 'ForfeitByUser') AND gaming_bonus_losts.date_time_lost BETWEEN @dateFrom AND @dateTo
              GROUP BY gaming_bonus_losts.client_stat_id) AS bonus_lost
               ON bonus_lost.client_stat_id = gaming_client_stats.client_stat_id
    WHERE    Rounds.client_id IS NOT NULL OR Transactions.client_id IS NOT NULL OR ggmps.client_id IS NOT NULL OR bonus_lost.client_stat_id IS NOT NULL OR free_rounds_transactions.client_id IS NOT NULL
    GROUP BY @queryDateIntervalID, client_id;

  -- Update chargebacks, adjustments & bonuses with gross revenue ratios
  UPDATE gaming_affiliate_client_activity_transfers
  SET sports_chargebacks=IFNULL(ROUND((sports_turnover/turnover)*chargebacks,2),0), sports_adjustments=IFNULL(ROUND((sports_turnover/turnover)*adjustments,2),0), sports_bonuses=IFNULL(ROUND((sports_turnover/turnover)*bonuses,2),0),
      casino_chargebacks=IFNULL(ROUND((casino_turnover/turnover)*chargebacks,2),0), casino_adjustments=IFNULL(ROUND((casino_turnover/turnover)*adjustments,2),0), casino_bonuses=IFNULL(ROUND((casino_turnover/turnover)*bonuses,2),0),
      poker_chargebacks=IFNULL(ROUND((poker_turnover/turnover)*chargebacks,2),0),   poker_adjustments=IFNULL(ROUND((poker_turnover/turnover)*adjustments,2),0),   poker_bonuses=IFNULL(ROUND((poker_turnover/turnover)*bonuses,2),0)
  WHERE query_date_interval_id=@queryDateIntervalID AND turnover!=0;

  -- UPDATE if all turnover is 0
  UPDATE gaming_affiliate_client_activity_transfers AS client_activity
  JOIN
  (
    SELECT client_activity.client_id, SUM(gaming_client_wager_stats.total_real_wagered) AS total_wagered,
      SUM(IF(gaming_client_wager_types.license_type_id=1, gaming_client_wager_stats.total_real_wagered, 0)) AS casino_wagered, SUM(IF(gaming_client_wager_types.license_type_id=2, gaming_client_wager_stats.total_real_wagered, 0)) AS poker_wagered, SUM(IF(gaming_client_wager_types.license_type_id=3, gaming_client_wager_stats.total_real_wagered, 0)) AS sports_wagered
    FROM gaming_affiliate_client_activity_transfers AS client_activity
    JOIN gaming_client_stats ON client_activity.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
    JOIN gaming_client_wager_stats ON gaming_client_stats.client_stat_id=gaming_client_wager_stats.client_stat_id
    JOIN gaming_client_wager_types ON gaming_client_wager_stats.client_wager_type_id=gaming_client_wager_types.client_wager_type_id
    WHERE client_activity.query_date_interval_id=@queryDateIntervalID AND client_activity.turnover=0
    GROUP BY client_activity.client_id
  ) AS Wagered ON client_activity.client_id=Wagered.client_id
  SET sports_chargebacks=IFNULL(ROUND((sports_wagered/total_wagered)*chargebacks,2),0), sports_adjustments=IFNULL(ROUND((sports_wagered/total_wagered)*adjustments,2),0), sports_bonuses=IFNULL(ROUND((sports_wagered/total_wagered)*bonuses,2),0),
      casino_chargebacks=IFNULL(ROUND((casino_wagered/total_wagered)*chargebacks,2),0), casino_adjustments=IFNULL(ROUND((casino_wagered/total_wagered)*adjustments,2),0), casino_bonuses=IFNULL(ROUND((casino_wagered/total_wagered)*bonuses,2),0),
      poker_chargebacks=IFNULL(ROUND((poker_wagered/total_wagered)*chargebacks,2),0),   poker_adjustments=IFNULL(ROUND((poker_wagered/total_wagered)*adjustments,2),0),   poker_bonuses=IFNULL(ROUND((poker_wagered/total_wagered)*bonuses,2),0)
  WHERE query_date_interval_id=@queryDateIntervalID AND turnover=0;

  SET statusCode=0;
END$$

DELIMITER ;

