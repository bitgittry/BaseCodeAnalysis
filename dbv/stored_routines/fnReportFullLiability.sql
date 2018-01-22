DROP FUNCTION IF EXISTS fnReport_full_liability;
DROP FUNCTION IF EXISTS fnReportFullLiability;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `fnReportFullLiability` (arg_datefrom datetime, 
                                                  arg_dateto datetime, 
                                                  arg_clientid varchar(255),
                                                  arg_onlydicrepancies int,
                                                  arg_dateToHourly datetime, 
                                                  arg_operator_id bigint) RETURNS varchar(255)
BEGIN

DECLARE timing varchar(255);
DECLARE tm bigint;


SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED ;
SET max_heap_table_size = 1024*1024*1024;
SET timing='';
SET tm= SYSDATE() + 0;
  
  
DROP TEMPORARY TABLE IF EXISTS `gaming_transactions_aggregation_report_players_liability_full`;

CREATE TEMPORARY TABLE `gaming_transactions_aggregation_report_players_liability_full` (
  `Player ID` bigint(20) PRIMARY KEY NOT NULL,
  `Player Name` varchar(100) NOT NULL,
  `Email` varchar(100) NOT NULL,
  `Country` varchar(100) NOT NULL,
  `Player Currency` varchar(100) NOT NULL,
  `Starting Balance` decimal(18,2) DEFAULT NULL,
  `Deposits` decimal(18,2) DEFAULT NULL,
  `Withdrawals` decimal(18,2) DEFAULT NULL,
  `Accepted Withdrawals` decimal(18,2) DEFAULT NULL,
  `Bonuses Made Real` decimal(18,2) DEFAULT NULL,
  `Bonuses Awarded` decimal(18,2) DEFAULT NULL,
  `Compensations` decimal(18,2) DEFAULT NULL,
  `Ending Balance` decimal(18,2) DEFAULT NULL,
  `Discrepancy` decimal(18,2) DEFAULT NULL,
  `Bet Volume` decimal(18,2) DEFAULT NULL,
  `Win Volume` decimal(18,2) DEFAULT NULL,
  `Timestamps` datetime DEFAULT NULL,
  `Casino Gross Revenue` decimal(18,2) DEFAULT NULL,
  `Casino Net Win` decimal(18,2) DEFAULT NULL,
  `Lifetime Value` decimal(18,2) DEFAULT NULL,
  `Starting Balance Base` decimal(18,2) DEFAULT NULL,
  `Bet Volume Base` decimal(18,2) DEFAULT NULL,
  `Win Volume Base` decimal(18,2) DEFAULT NULL,
  `Deposits Base` decimal(18,2) DEFAULT NULL,
  `Withdrawals Base` decimal(18,2) DEFAULT NULL,
  `Accepted Withdrawals Base` decimal(18,2) DEFAULT NULL,
  `Bonuses Made Real Base` decimal(18,2) DEFAULT NULL,
  `Bonuses Awarded Base` decimal(18,2) DEFAULT NULL,
  `Compensations Base` decimal(18,2) DEFAULT NULL,
  `Ending Balance Base` decimal(18,2) DEFAULT NULL,
  `Discrepancy Base` decimal(18,2) DEFAULT NULL,
  `Casino Gross Revenue Base` decimal(18,2) DEFAULT NULL,
  `Casino Net Win Base` decimal(18,2) DEFAULT NULL,
  `Self Excluded` varchar(10) DEFAULT NULL,
  `Allowed Login` varchar(10) DEFAULT NULL,
  `Receive Promotions` varchar(10) NOT NULL,
  `ChargeBack` decimal(18,2) DEFAULT NULL,
  `Returns` decimal(18,2) DEFAULT NULL,
  `Total Credits` decimal(18,2) DEFAULT NULL,
  `Total Debits` decimal(18,2) DEFAULT NULL,
  `Loyalty Points Redemption` decimal(18,2) DEFAULT NULL,
  
  `tmp_current_real_balance` decimal(18,2) DEFAULT NULL,
  `tmp_playercardfee` decimal(18,2) DEFAULT NULL,
  `tmp_LoyaltyPointsRedemption` decimal(18,2) DEFAULT NULL,
  `tmp_playercardfeebase` decimal(18,2) DEFAULT NULL,
  `tmp_BetBase` decimal(18,2) DEFAULT NULL,
  `tmp_WinBase` decimal(18,2) DEFAULT NULL,
  `tmp_Bet` decimal(18,2) DEFAULT NULL,
  `tmp_Win` decimal(18,2) DEFAULT NULL,
  `tmp_HBet` decimal(18,2) DEFAULT NULL,
  `tmp_HBetBase` decimal(18,2) DEFAULT NULL,
  `tmp_HWin` decimal(18,2) DEFAULT NULL,
  `tmp_HWinBase` decimal(18,2) DEFAULT NULL,
  `tmp_dc_type` varchar(255) DEFAULT NULL,
  `tmp_total_dc` decimal(18,2) DEFAULT NULL,
  `tmp_exchange_rate` decimal(18,2) DEFAULT NULL,  
  `tmp_exchange_rate_start` decimal(18,2) DEFAULT NULL,
  `tmp_exchange_rate_end` decimal(18,2) DEFAULT NULL

  
) ENGINE=MEMORY DEFAULT CHARSET=utf8;
  

  
  SET timing=concat(timing,'create_table=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  

--  fill the table with all the players info
INSERT INTO gaming_transactions_aggregation_report_players_liability_full(
  `Player ID`, 
  `Player Name`, 
  `Email`, 
  `Country`, 
  `Player Currency`,
  `Allowed Login`, 
  `Receive Promotions`,
  `Starting Balance`,
  `Ending Balance`,
  `tmp_current_real_balance`,
  `Lifetime Value`,
  `tmp_exchange_rate`
  )
SELECT
  gaming_clients.client_id AS `Player ID`, 
  IFNULL(CONCAT(gaming_clients.name,' ',gaming_clients.surname),'n.a.') AS `Player Name`, 
  IFNULL(gaming_clients.email, 'n.a.') AS `Email`, 
  gaming_countries.name AS `Country`, 
  gaming_currency.currency_code AS `Player Currency`,
  IF (gaming_clients.is_active, 'Y','N') AS `Allowed Login`, 
	IF (gaming_clients.receive_promotional_by_email, 'Y', 'N') AS `Receive Promotions`,
  ROUND(IFNULL(balance_start.real_balance, 0)/100,2) AS `Starting Balance`, 
  ROUND((IFNULL(balance_end.real_balance, gaming_client_stats.current_real_balance)/100),2) AS `Ending Balance`,
  ROUND(gaming_client_stats.current_real_balance,2) ,
  ROUND((((total_real_played-total_real_won)-(total_bonus_transferred+total_bonus_win_locked_transferred)-(total_adjustments+total_jackpot_contributions))/100),2) ,
  ROUND(gaming_operator_currency.exchange_rate,2) 
  FROM gaming_clients 
  JOIN gaming_client_stats ON gaming_clients.client_id=gaming_client_stats.client_id 
    AND gaming_clients.is_test_player=0 AND sign_up_date < arg_dateto
    AND gaming_clients.client_id = CASE WHEN arg_clientid = '' THEN gaming_clients.client_id ELSE arg_clientid END
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = gaming_client_stats.currency_id
  JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1
  JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
  LEFT JOIN gaming_client_daily_balances AS balance_start 
	ON TO_DAYS(arg_datefrom) > balance_start.date_from_int AND TO_DAYS(arg_datefrom) <= balance_start.date_to_int AND balance_start.client_stat_id = gaming_client_stats.client_stat_id
  LEFT JOIN gaming_client_daily_balances AS balance_end  
	ON TO_DAYS(arg_dateto) + 1 > balance_end.date_from_int AND TO_DAYS(arg_dateto) + 1 <= balance_end.date_to_int AND balance_end.client_stat_id = gaming_client_stats.client_stat_id
  ;
  

  SET timing=concat(timing,'players=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  
 -- update the start and the end rate exchange
  update gaming_transactions_aggregation_report_players_liability_full tbl1
  INNER JOIN (select gaming_client_stats.client_stat_id as client_stat_id, 
        exchange_rate_start.exchange_rate as rate_start
  FROM gaming_client_stats 
  LEFT JOIN (select currency_id, exchange_rate from history_gaming_operator_currency where 
    arg_datefrom between history_datetime_from AND history_datetime_to AND operator_id=arg_operator_id 
      and currency_id in (select distinct(currency_id) from gaming_client_stats)) AS exchange_rate_start 
    ON gaming_client_stats.currency_id=exchange_rate_start.currency_id
    ) tbl2
    ON tbl1.`Player ID` = tbl2.client_stat_id
    set tbl1.`tmp_exchange_rate_start`= rate_start;
  
  update gaming_transactions_aggregation_report_players_liability_full tbl1
  INNER JOIN (select gaming_client_stats.client_stat_id as client_stat_id, 
        exchange_rate_end.exchange_rate as rate_end
  FROM gaming_client_stats 
  LEFT JOIN (select currency_id, exchange_rate from history_gaming_operator_currency where 
    arg_dateto between history_datetime_from AND history_datetime_to AND operator_id=arg_operator_id
      and currency_id in (select distinct(currency_id) from gaming_client_stats)) AS exchange_rate_end
    ON gaming_client_stats.currency_id=exchange_rate_end.currency_id
    ) tbl2
    ON tbl1.`Player ID` = tbl2.client_stat_id
    set tbl1.`tmp_exchange_rate_end`= rate_end;

  SET timing=concat(timing,'rate_exchange=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  


  
-- transactions
  update gaming_transactions_aggregation_report_players_liability_full tbl1
  INNER JOIN (
     SELECT gaming_transactions.client_stat_id, 
      (SUM(IF(CompensationTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS Compensations,
      (SUM(IF(BonusTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS Bonuses,
      (SUM(IF(BonusAwardedTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS BonusesAwarded,
      (SUM(IF(DepositTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS Deposits,
      (SUM(IF(WithdrawalTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total*-1))) AS Withdrawals,
      (SUM(IF(PlayerCardFee.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS PlayerCardFee,
      (SUM(IF(LoyaltyPointsRedemption.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total))) AS LoyaltyPointsRedemption,
      (SUM(IF(CompensationTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base))) AS CompensationsBase,
      (SUM(IF(BonusTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base))) AS BonusesBase,
      (SUM(IF(BonusAwardedTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base))) AS BonusesAwardedBase,
      (SUM(IF(DepositTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base))) AS DepositsBase,
      (SUM(IF(WithdrawalTransactions.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base*-1))) AS WithdrawalsBase,
      (SUM(IF(PlayerCardFee.payment_transaction_type_id IS NULL, 0, gaming_transactions.amount_total_base))) AS PlayerCardFeeBase,
      gaming_transactions.timestamp As Timestamps
   FROM gaming_transactions
    JOIN gaming_client_stats ON gaming_transactions.timestamp BETWEEN arg_datefrom AND arg_dateto 
    AND gaming_transactions.client_stat_id=gaming_client_stats.client_stat_id
    AND gaming_transactions.client_stat_id = CASE WHEN arg_clientid = '' THEN gaming_transactions.client_stat_id ELSE arg_clientid END
    JOIN gaming_payment_transaction_type AS RealMoneyTransactions ON 
      RealMoneyTransactions.name IN ('Cashback','CashbackCancelled','BonusRequirementMet','BonusAwarded','Compensation','Winnings','Correction','TournamentWin','Deposit','DepositCancelled','Withdrawal','WithdrawalRequest','WithdrawalCancelled','BadDept','BonusTurnedReal','RedeemBonus','LoyaltyPointsRedemption','CashBonus','BonusCashExchange','PlayerCardFee') AND
      gaming_transactions.payment_transaction_type_id=RealMoneyTransactions.payment_transaction_type_id
    LEFT JOIN gaming_payment_transaction_type AS CompensationTransactions ON 
      CompensationTransactions.name IN ('Cashback','CashbackCancelled','Compensation','Winnings','Correction','TournamentWin','BadDept','LoyaltyPointsRedemption') AND
      gaming_transactions.payment_transaction_type_id=CompensationTransactions.payment_transaction_type_id 
    LEFT JOIN gaming_payment_transaction_type AS BonusTransactions ON 
      BonusTransactions.name IN ('BonusRequirementMet','BonusTurnedReal','RedeemBonus','CashBonus','BonusCashExchange') AND
      gaming_transactions.payment_transaction_type_id=BonusTransactions.payment_transaction_type_id
    LEFT JOIN gaming_payment_transaction_type AS BonusAwardedTransactions ON 
      BonusAwardedTransactions.name IN ('BonusAwarded') AND
      gaming_transactions.payment_transaction_type_id=BonusAwardedTransactions.payment_transaction_type_id
    LEFT JOIN gaming_payment_transaction_type AS DepositTransactions ON 
      DepositTransactions.name IN ('Deposit','DepositCancelled') AND
      gaming_transactions.payment_transaction_type_id=DepositTransactions.payment_transaction_type_id 
    LEFT JOIN gaming_payment_transaction_type AS WithdrawalTransactions ON 
      WithdrawalTransactions.name IN ('Withdrawal','WithdrawalRequest','WithdrawalCancelled') AND
      gaming_transactions.payment_transaction_type_id=WithdrawalTransactions.payment_transaction_type_id 
    LEFT JOIN gaming_payment_transaction_type AS PlayerCardFee ON 
      PlayerCardFee.name IN ('PlayerCardFee') AND
      gaming_transactions.payment_transaction_type_id=PlayerCardFee.payment_transaction_type_id 
    LEFT JOIN gaming_payment_transaction_type AS LoyaltyPointsRedemption ON 
      LoyaltyPointsRedemption.name IN ('LoyaltyPointsRedemption') AND
      gaming_transactions.payment_transaction_type_id=LoyaltyPointsRedemption.payment_transaction_type_id     
    GROUP BY gaming_transactions.client_stat_id
    HAVING (Compensations!=0 OR Bonuses!=0 OR Deposits!=0 OR Withdrawals!=0)) tbl2
    ON tbl1.`Player ID` = tbl2.client_stat_id
    set tbl1.`Deposits`= ROUND(IFNULL(tbl2.Deposits/100, 0) ,2),
    tbl1.`Withdrawals`= ROUND(IFNULL(tbl2.Withdrawals/100, 0) ,2),
    tbl1.`Bonuses Made Real`= ROUND(IFNULL(tbl2.Bonuses/100, 0) ,2),
    tbl1.`Bonuses Awarded`= ROUND(IFNULL(tbl2.BonusesAwarded/100, 0) ,2),
    tbl1.`Compensations`= ROUND(IFNULL(tbl2.Compensations/100, 0) ,2),
    tbl1.`tmp_playercardfee`= ROUND(IFNULL(tbl2.PlayerCardFee/100, 0) ,2),
    tbl1.`tmp_LoyaltyPointsRedemption`= ROUND(IFNULL(tbl2.LoyaltyPointsRedemption/100, 0) ,2),
    tbl1.`Compensations Base`= ROUND(IFNULL(tbl2.CompensationsBase/100, 0) ,2),
    tbl1.`Bonuses Made Real Base`= ROUND(IFNULL(tbl2.BonusesBase/100, 0) ,2),
    tbl1.`Bonuses Awarded Base`= ROUND(IFNULL(tbl2.BonusesAwardedBase/100, 0) ,2),
    tbl1.`Deposits Base`= ROUND(IFNULL(tbl2.DepositsBase/100, 0) ,2),
    tbl1.`Withdrawals Base`= ROUND(IFNULL(tbl2.WithdrawalsBase/100, 0) ,2),
    tbl1.`tmp_playercardfeebase`= ROUND(IFNULL(tbl2.playercardfeebase/100, 0) ,2),
    tbl1.`Timestamps`= tbl2.Timestamps;


    SET timing=concat(timing,'transactions=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  



-- wagering in base currecny
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (
            SELECT game_transactions.client_stat_id, 
            IFNULL((SUM(bet_real)),0) AS `BetBase`, 
            IFNULL((SUM(win_real)),0) AS `WinBase`
            FROM gaming_game_transactions_aggregation_player_game AS game_transactions 
            WHERE game_transactions.date_from BETWEEN arg_datefrom AND arg_dateto 
            AND game_transactions.client_stat_id = CASE WHEN arg_clientid = '' THEN game_transactions.client_stat_id ELSE arg_clientid END
            GROUP BY game_transactions.client_stat_id
            HAVING (BetBase!= 0 OR WinBase!=0)
            ) AS tbl2 
            ON tbl1.`Player ID`=tbl2.client_stat_id
      set tbl1.`tmp_BetBase`= ROUND(IFNULL(tbl2.BetBase/100, 0) ,2),
      tbl1.`tmp_WinBase`= ROUND(IFNULL(tbl2.WinBase/100, 0) ,2);
      

-- wagering in player currency      
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (
            SELECT game_transactions.client_stat_id, 
            IFNULL((SUM(bet_real)),0) AS `Bet`, 
            IFNULL((SUM(win_real)),0) AS `Win`
            FROM gaming_game_transactions_aggregation_player_game_pc AS game_transactions 
            WHERE game_transactions.date_from BETWEEN arg_datefrom AND arg_dateto 
            GROUP BY game_transactions.client_stat_id
            HAVING (Bet!= 0 OR Win!=0)
            ) AS tbl2 
            ON tbl1.`Player ID`=tbl2.client_stat_id
      set tbl1.`tmp_Bet`= ROUND(IFNULL(tbl2.Bet/100, 0) ,2),
      tbl1.`tmp_Win`= ROUND(IFNULL(tbl2.Win/100, 0) ,2);



    SET timing=concat(timing,'wagering=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  
  
-- last hour correction
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (
        SELECT gaming_game_plays.client_stat_id, 
        SUM(IF(bet_type.payment_transaction_type_id IS NULL, 0, gaming_game_plays.amount_real*gaming_game_plays.sign_mult*-1)) AS HBet, 
        (SUM(IF(bet_type.payment_transaction_type_id IS NULL, 0, (gaming_game_plays.amount_real*gaming_game_plays.sign_mult*-1)/exchange_rate))) AS HBetBase,
        SUM(IF(win_type.payment_transaction_type_id IS NULL, 0, gaming_game_plays.amount_real)) AS HWin, 
        (SUM(IF(win_type.payment_transaction_type_id IS NULL, 0, gaming_game_plays.amount_real/exchange_rate))) AS HWinBase
        FROM gaming_game_plays
        JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet','Win','BetCancelled') AND gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
        LEFT JOIN gaming_payment_transaction_type AS bet_type ON bet_type.name IN ('Bet','BetCancelled') AND gaming_game_plays.payment_transaction_type_id=bet_type.payment_transaction_type_id
        LEFT JOIN gaming_payment_transaction_type AS win_type ON win_type.name IN ('Win') AND gaming_game_plays.payment_transaction_type_id=win_type.payment_transaction_type_id
        WHERE arg_dateToHourly IS NOT NULL AND gaming_game_plays.timestamp>arg_dateToHourly 
        GROUP BY gaming_game_plays.client_stat_id
        HAVING (HBet!= 0 OR HWin!=0)
      ) AS tbl2 
      ON tbl1.`Player ID`=tbl2.client_stat_id
      set tbl1.`tmp_HBet`= ROUND(IFNULL(tbl2.HBet/100, 0) ,2),
      tbl1.`tmp_HBetBase`= ROUND(IFNULL(tbl2.HBetBase/100, 0) ,2),
      tbl1.`tmp_HWin`= ROUND(IFNULL(tbl2.HWin/100, 0) ,2),
      tbl1.`tmp_HWinBase`= ROUND(IFNULL(tbl2.HWinBase/100, 0) ,2);


SET timing=concat(timing,'last_hour_correction=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;

    -- player restrictions
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      LEFT JOIN (
      SELECT gaming_player_restrictions.client_id as client_stat_id    
      FROM gaming_player_restrictions
      JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_login=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
      WHERE gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date
      GROUP BY gaming_player_restrictions.client_id
      ) AS tbl2 
      ON tbl1.`Player ID`=tbl2.client_stat_id
      SET `Self Excluded` = IF(tbl2.client_stat_id IS NULL, 'N','Y');
  
  
  SET timing=concat(timing,'player_restrictions=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
  
  
    -- withdrawals   
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (  
      SELECT gaming_client_stats.client_id as client_stat_id, 
      SUM((gaming_balance_history.amount/100)) AS withdrawal_amount,
      SUM((gaming_balance_history.amount_base/100)) AS withdrawal_amount_base 
      FROM gaming_client_stats
      JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name IN ('Withdrawal','WithdrawalRequest','Cashback')
      JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.payment_transaction_status_id = 1
      JOIN gaming_balance_history ON
        gaming_balance_history.timestamp BETWEEN arg_datefrom AND arg_dateto AND
        gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
        AND gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
        AND gaming_balance_history.client_stat_id = gaming_client_stats.client_stat_id 
        AND gaming_balance_history.client_stat_id = CASE WHEN arg_clientid = '' THEN gaming_balance_history.client_stat_id ELSE arg_clientid END
      JOIN gaming_balance_accounts ON gaming_balance_history.balance_account_id=gaming_balance_accounts.balance_account_id
      JOIN gaming_payment_method ON gaming_balance_history.sub_payment_method_id=gaming_payment_method.payment_method_id
      GROUP BY gaming_client_stats.client_id
     ) AS tbl2 
     ON tbl1.`Player ID`=tbl2.client_stat_id
     SET tbl1.`Accepted Withdrawals`= ROUND(IFNULL(tbl2.withdrawal_amount, 0) ,2),
      tbl1.`Accepted Withdrawals Base`= ROUND(IFNULL(tbl2.withdrawal_amount_base, 0) ,2);
  
  
    SET timing=concat(timing,'withdrawals=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
    
    
 -- Total Credits and Debits
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (  
    	SELECT gaming_client_stats.client_id as client_stat_id, 
    		SUM(IF(dc_type = 'credit', IFNULL(amount_base, 0), 0)/100) AS total_credit, 
        SUM(IF(dc_type = 'debit', IFNULL(amount_base, 0), 0)/100) AS total_debit,
    		dc_type	
    	FROM accounting_dc_notes
    	JOIN accounting_dc_note_types ON accounting_dc_notes.dc_note_type_id = accounting_dc_note_types.dc_note_type_id
    	LEFT JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = accounting_dc_notes.client_stat_id
    	LEFT JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id 
    	WHERE note_type NOT IN ('JackpotRefund', 'Chargeback', 'Chargeback Reversal', 'Cancel Chargeback', 'Cancel Chargeback Reversal') AND 
    		timestamp BETWEEN arg_datefrom AND arg_dateto 
        AND (is_test_player = 0 OR gaming_clients.client_id IS NULL)
    	) AS tbl2 
      ON tbl1.`Player ID`=tbl2.client_stat_id
      SET tbl1.`tmp_dc_type`=dc_type,
      tbl1.`Total Credits`= ROUND(total_credit ,2),
      tbl1.`Total Debits` =  ROUND(total_debit ,2);
      
      
          SET timing=concat(timing,'Total_Credits_and_Debits=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
          
          
    -- chargebacks
    update gaming_transactions_aggregation_report_players_liability_full tbl1
      INNER JOIN (  
      SELECT gaming_clients.client_id as client_stat_id, 
      SUM(IFNULL(IF(is_credit_card = 1 AND note_type IN ('Chargeback', 'Cancel Chargeback'), accounting_dc_notes.amount_base, NULL), 0) -
      IFNULL(IF(is_credit_card = 1 AND note_type IN ('Chargeback Reversal', 'Cancel Chargeback Reversal'), accounting_dc_notes.amount_base, NULL), 0)) AS Chargeback,
      SUM(IFNULL(IF(is_credit_card = 0 AND note_type IN ('Chargeback', 'Cancel Chargeback'), accounting_dc_notes.amount_base, NULL), 0) -
      IFNULL(IF(is_credit_card = 0 AND note_type IN ('Chargeback Reversal', 'Cancel Chargeback Reversal'), accounting_dc_notes.amount_base, NULL),0)) AS Returns
      FROM gaming_balance_history
      JOIN gaming_clients ON gaming_clients.client_id = gaming_balance_history.client_id AND gaming_clients.is_test_player = 0
      AND gaming_clients.client_id = CASE WHEN arg_clientid = '' THEN gaming_clients.client_id ELSE arg_clientid END
      JOIN gaming_payment_method ON gaming_balance_history.payment_method_id = gaming_payment_method.payment_method_id 
      JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'Deposit' AND 
      gaming_balance_history.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id
      JOIN accounting_dc_notes ON accounting_dc_notes.balance_history_id = gaming_balance_history.balance_history_id
      JOIN accounting_dc_note_types ON accounting_dc_notes.dc_note_type_id = accounting_dc_note_types.dc_note_type_id AND 
      accounting_dc_note_types.note_type IN ('Chargeback', 'Cancel Chargeback', 'Chargeback Reversal', 'Cancel Chargeback Reversal')
      WHERE accounting_dc_notes.timestamp BETWEEN arg_datefrom AND arg_dateto
      GROUP BY gaming_clients.client_id
      ) AS tbl2 
      ON tbl1.`Player ID`=tbl2.client_stat_id
      SET tbl1.`ChargeBack`= ROUND(IFNULL(tbl2.ChargeBack/100, 0) ,2),
      tbl1.`Returns`= ROUND(IFNULL(tbl2.Returns/100, 0) ,2);

       SET timing=concat(timing,'chargebacks=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
       
       
-- final computations using data recorded previously in the table  
      update gaming_transactions_aggregation_report_players_liability_full
      set  `Discrepancy`=	ROUND(IFNULL(Deposits, 0) 
                      		- IFNULL(Withdrawals, 0) 
                      		- ((IFNULL(tmp_Bet,0)+IFNULL(tmp_HBet,0))) 
                      		+ ((IFNULL(tmp_Win,0)+IFNULL(tmp_HWin,0))) 
                      		+ (IFNULL(tmp_PlayerCardFee, 0))
                      		+ IFNULL(Compensations, 0) 
                      		+ IFNULL(`Starting Balance`, 0)
                      		- (IFNULL(`Ending Balance`, tmp_current_real_balance))
                          + (IFNULL(`Bonuses Made Real`, 0)),2),

           `Bet Volume` =	ROUND(((IFNULL(tmp_Bet,0)+IFNULL(tmp_HBet,0))),2), 
	         `Win Volume` =  ROUND(((IFNULL(tmp_Win,0)+IFNULL(tmp_HWin,0))),2),
           `Casino Gross Revenue` =  ROUND((IFNULL(tmp_Bet-tmp_Win, 0)+IFNULL(tmp_HBet-tmp_HWin, 0)),2), 
           `Casino Net Win` =  ROUND(((IFNULL(tmp_Bet-tmp_Win, 0)+IFNULL(tmp_HBet-tmp_HWin, 0)-IFNULL(`Bonuses Made Real`,0)-IFNULL(Compensations,0))),2),
           `Starting Balance Base` = ROUND((IFNULL(`Starting Balance`, 0)/IFNULL(tmp_exchange_rate_start, tmp_exchange_rate)),2),
           `Bet Volume Base` = ROUND(((IFNULL(tmp_BetBase,0)+IFNULL(tmp_HBetBase,0))),2), 
           `Win Volume Base` = ROUND(((IFNULL(tmp_WinBase,0)+IFNULL(tmp_HWinBase,0))),2),
           `Ending Balance Base` = ROUND(((IFNULL(`Ending Balance`, tmp_current_real_balance)/IFNULL(tmp_exchange_rate_end, tmp_exchange_rate))),2),

           `Discrepancy Base` = ROUND(IFNULL(`Deposits Base`, 0) 
                            		- IFNULL(`Withdrawals Base`, 0) 
                            		- ((IFNULL(tmp_BetBase,0)+IFNULL(tmp_HBetBase,0))) 
                            		+ ((IFNULL(tmp_WinBase,0)+IFNULL(tmp_HWinBase,0))) 
                            		+ IFNULL(tmp_playercardfeebase, 0)
                            		+ IFNULL(`Compensations Base`, 0) 
                            		+ (IFNULL(`Starting Balance`, 0)/IFNULL(tmp_exchange_rate_start, tmp_exchange_rate)) 
                            		- ((IFNULL(`Ending Balance`, tmp_current_real_balance)/IFNULL(tmp_exchange_rate_end, tmp_exchange_rate))) 
                            		+ IFNULL(`Bonuses Made Real Base`, 0),2),
  	       `Casino Gross Revenue Base` = ROUND((IFNULL(tmp_BetBase-tmp_WinBase,0)+IFNULL(tmp_HBetBase-tmp_HWinBase,0)),2),
           `Casino Net Win Base` = ROUND(((IFNULL(tmp_BetBase-tmp_WinBase,0)+IFNULL(tmp_HBetBase-tmp_HWinBase,0)-IFNULL(`Bonuses Made Real Base`,0)-IFNULL(`Compensations Base`,0))),2),
           `Loyalty Points Redemption` = (IFNULL(tmp_LoyaltyPointsRedemption, 0)/IFNULL(tmp_exchange_rate_start, tmp_exchange_rate));

    
           SET timing=concat(timing,'computations=', CAST(SYSDATE() + 0 -tm AS CHAR),' / '); SET tm=SYSDATE() + 0;
    
    
	RETURN timing;
END$$

DELIMITER ;



