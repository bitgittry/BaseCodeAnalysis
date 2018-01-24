DROP procedure IF EXISTS `TransactionChargeInactiveAccounts`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionChargeInactiveAccounts`()
root: BEGIN

	-- Misc
	DECLARE CounterID, BonusCounterID BIGINT;
	DECLARE CurTimeStamp DATETIME DEFAULT NOW();
	DECLARE Enabled TINYINT(1) DEFAULT 0;

  -- Configuration Settings 
  DECLARE ActiveOnBets, ActiveOnWithdrawals, ActiveOnLogins, ActiveOnDeposits tinyint(1) DEFAULT 0;
  DECLARE ActiveOnRegistration tinyint(1) DEFAULT 1;
  DECLARE DaysOfInactivity INT;
  DECLARE AutomaticallyTagPlayersAsDormant tinyint(1) DEFAULT 0;

  -- Action Settings
  DECLARE AccountClosureType VARCHAR(80) DEFAULT 'closed';
  DECLARE KYCCheckedPlayerSelection, PlayerActivationSelected VARCHAR(80);
  DECLARE AutomaticallygenerateDormantFeeForPlayers, AutomaticallyCloseDeactivatePlayerAccounts, ClearAnyRemainingBalance, IncludeClosedPlayerAccounts tinyint(1) DEFAULT 0;
  DECLARE DaysOfBeingTaggedDormant, DaysOfAccountClosure, DaysToAutomaticallyGenrateDormantFee INT;


    DECLARE clientID bigint DEFAULT -1; 
    DECLARE accountClosedStatusID bigint DEFAULT NULL; 
    DECLARE attributeAccountClosedExists TINYINT(1) DEFAULT 0;  
    DECLARE attributeAccountClosedIsFirstAndOnlyAttribute TINYINT(1) DEFAULT 0;
    DECLARE notMoreRows TINYINT(1) DEFAULT 0;
    DECLARE dormantCursor CURSOR FOR
      SELECT gaming_clients.client_id 
        FROM gaming_clients
		    JOIN  gaming_client_stats ON 
                gaming_clients.client_id = gaming_client_stats.client_id AND 
                is_account_closed = 0 AND 
                is_dormant_account = 1 AND 
                IF(AccountClosureType = 'inactive', gaming_clients.is_active = 1, 1=1)
        JOIN gaming_clients_login_attempts_totals ON 
                gaming_clients_login_attempts_totals.client_id = gaming_clients.client_id            
      WHERE 
        (kyc_checked_status_id IS NULL OR kyc_checked_status_id NOT IN (IFNULL(KYCCheckedPlayerSelection, -1))) AND 
        gaming_clients.account_activated NOT IN (IFNULL(PlayerActivationSelected, -1)) AND 
        TIMESTAMPDIFF(DAY, IFNULL(last_dormant_date, NOW()), NOW()) >= DaysOfBeingTaggedDormant;      

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET notMoreRows = TRUE;
    

  -- Get Game Settings
  SELECT 
    gsInactivityFee.value_bool as vbInactivityFee, 
    gsDormantAccountType.value_string as vbDormantAccountType
  INTO 
    Enabled, 
    AccountClosureType
	FROM gaming_settings AS gsInactivityFee 
	JOIN gaming_settings AS gsDormantAccountType 
    ON (gsDormantAccountType.name = 'DORMANT_ACCOUNT_CLOSURE_TYPE')
	WHERE gsInactivityFee.name = 'INACTIVITY_FEE_ENABLED';

	IF Enabled =0 THEN
		LEAVE root;
	END IF;

  -- Get Dormant Account Management Settings
  SELECT
    days_of_inactivity, 
    selected_player_account_statuses,
    kyc_checked_statuses,
    days_of_account_closure,
    clear_any_remaining_balance,
    days_of_being_tagged_dormant,
    days_to_automatically_generate_dormant_fee,
    automatically_tag_players_as_dormant,
    automatically_generate_dormant_fee,
    close_deactivate_player_account,
    include_closed_player_accounts,
    active_on_deposits,
    active_on_logins,
    active_on_withdrawals,
    active_on_bets
	INTO 
    DaysOfInactivity, 
    PlayerActivationSelected, 
    KYCCheckedPlayerSelection, 
    DaysOfAccountClosure, 
    ClearAnyRemainingBalance,
    DaysOfBeingTaggedDormant, 
    DaysToAutomaticallyGenrateDormantFee,
    AutomaticallyTagPlayersAsDormant,
    AutomaticallygenerateDormantFeeForPlayers,
    AutomaticallyCloseDeactivatePlayerAccounts,
    IncludeClosedPlayerAccounts,
    ActiveOnDeposits,
    ActiveOnLogins,
    ActiveOnWithdrawals,
    ActiveOnBets
	FROM gaming_dormant_account_settings 
  WHERE dormant_account_setting_type = 'InactivityFee'
  LIMIT 1;
  
  -- Remove Dormant Status
  UPDATE gaming_clients
  JOIN  gaming_client_stats
    ON gaming_clients.client_id = gaming_client_stats.client_id
      AND is_account_closed = 0 
      AND is_dormant_account = 1
  JOIN gaming_clients_login_attempts_totals 
    ON gaming_clients_login_attempts_totals.client_id = gaming_clients.client_id
  SET 
    last_dormant_date = NOW(),
    is_dormant_account = 0,
    last_inactive_fee_date = NULL
  WHERE
    (ActiveOnDeposits = 1 AND TIMESTAMPDIFF(DAY, IFNULL(last_deposited_date, sign_up_date), NOW()) < DaysOfInactivity)
    OR (ActiveOnWithdrawals = 1 AND TIMESTAMPDIFF(DAY, IFNULL(last_withdrawn_date, sign_up_date), NOW()) < DaysOfInactivity)
    OR (ActiveOnLogins = 1 AND TIMESTAMPDIFF(DAY, IFNULL(gaming_clients_login_attempts_totals.last_success, sign_up_date), NOW()) < DaysOfInactivity)
    OR (ActiveOnBets = 1 AND TIMESTAMPDIFF(DAY, IFNULL(last_played_date, sign_up_date), NOW()) < DaysOfInactivity);
    

  -- Set Dormant Status
  IF AutomaticallyTagPlayersAsDormant THEN 
      
    UPDATE gaming_clients
    JOIN  gaming_client_stats
      ON gaming_clients.client_id = gaming_client_stats.client_id
        AND is_account_closed = 0 
        AND is_dormant_account = 0
    JOIN gaming_clients_login_attempts_totals 
      ON gaming_clients_login_attempts_totals.client_id = gaming_clients.client_id
    SET 
      last_dormant_date = NOW(),
      is_dormant_account = 1
    WHERE
      (ActiveOnDeposits = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_deposited_date, sign_up_date), NOW()) >= DaysOfInactivity)
      AND (ActiveOnWithdrawals = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_withdrawn_date, sign_up_date), NOW()) >= DaysOfInactivity)
      AND (ActiveOnLogins = 0 OR TIMESTAMPDIFF(DAY, IFNULL(gaming_clients_login_attempts_totals.last_success, sign_up_date), NOW()) >= DaysOfInactivity)
      AND (ActiveOnBets = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_played_date, sign_up_date), NOW()) >= DaysOfInactivity)
			AND TIMESTAMPDIFF(DAY, IFNULL(sign_up_date, NOW()), NOW()) >= DaysOfInactivity;
			
  END IF;

  -- Insert into transactions Counter
	INSERT INTO gaming_transaction_counter (date_created) VALUES (CurTimeStamp);
	SET CounterID = LAST_INSERT_ID();  

  -- Automatically Generate Fee
  IF AutomaticallygenerateDormantFeeForPlayers THEN

    INSERT INTO gaming_transaction_counter_amounts 
      (
        transaction_counter_id, 
        client_stat_id, 
        amount
      )
    SELECT 
      CounterID,
      client_stat_id,
      LEAST(current_real_balance, inactivity_fee) * -1 AS fee  
    FROM gaming_clients
    JOIN gaming_client_stats 
      ON gaming_clients.client_id = gaming_client_stats.client_id 
       AND current_real_balance > 0
    JOIN gaming_payment_amounts
      ON gaming_client_stats.currency_id = gaming_payment_amounts.currency_id
        AND IF(IncludeClosedPlayerAccounts, (is_account_closed OR is_dormant_account), (is_dormant_account AND is_account_closed = 0))
    JOIN gaming_clients_login_attempts_totals 
      ON gaming_clients.client_id = gaming_clients_login_attempts_totals.client_id 
    WHERE 
      TIMESTAMPDIFF(DAY, IFNULL(last_inactive_fee_date, DATE_SUB(NOW(), INTERVAL DaysToAutomaticallyGenrateDormantFee DAY)), NOW()) >= DaysToAutomaticallyGenrateDormantFee;
    
    UPDATE gaming_client_stats 
    JOIN gaming_transaction_counter_amounts 
      ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id
    SET
      last_inactive_fee_date = CurTimeStamp
    WHERE
      transaction_counter_id = CounterID;

  END IF;

  -- Automatically Close Or Deactivate Accounts
  IF AutomaticallyCloseDeactivatePlayerAccounts THEN
    

    -- 
        IF (AccountClosureType = 'closed') THEN
    
          SELECT        
            count(*) = 1 and SUM(gaming_player_status_attributes.attribute_name = 'account_closed' AND value = 'true') = 1 AS attributeAccountClosedIsFirstAndOnlyAttribute
          INTO 
              attributeAccountClosedIsFirstAndOnlyAttribute
          FROM gaming_player_status_attributes_values
          JOIN gaming_player_statuses ON gaming_player_status_attributes_values.player_status_id = gaming_player_statuses.player_status_id
          JOIN gaming_player_status_attributes ON gaming_player_status_attributes_values.player_status_attribute_id = gaming_player_status_attributes.attribute_id
          WHERE
          	 gaming_player_status_attributes_values.is_hidden = 0 AND gaming_player_statuses.is_hidden = 0
          GROUP BY gaming_player_statuses.priority 
          ORDER BY priority LIMIT 1;
      
          SELECT 
            NOT SUM(gaming_player_status_attributes.attribute_name = 'account_closed') =0 AS accountClosedExists
          INTO 
            attributeAccountClosedExists
          FROM gaming_player_status_attributes_values
          JOIN gaming_player_statuses ON gaming_player_status_attributes_values.player_status_id = gaming_player_statuses.player_status_id
          JOIN gaming_player_status_attributes ON gaming_player_status_attributes_values.player_status_attribute_id = gaming_player_status_attributes.attribute_id
          WHERE gaming_player_status_attributes_values.is_hidden = 0 AND gaming_player_statuses.is_hidden = 0;
      
          SELECT 
           MIN( gaming_player_statuses.player_status_id) INTO accountClosedStatusID
          FROM gaming_player_status_attributes_values
          JOIN gaming_player_statuses ON gaming_player_status_attributes_values.player_status_id = gaming_player_statuses.player_status_id
          JOIN gaming_player_status_attributes ON gaming_player_status_attributes_values.player_status_attribute_id = gaming_player_status_attributes.attribute_id
          WHERE
          	 gaming_player_status_attributes_values.is_hidden = 0 AND gaming_player_statuses.is_hidden = 0 AND
             gaming_player_status_attributes.attribute_name = 'account_closed';
    
       END IF;
    
        IF (AccountClosureType = 'closed' AND (NOT attributeAccountClosedExists OR attributeAccountClosedIsFirstAndOnlyAttribute)) THEN  
            
    UPDATE gaming_clients
            JOIN  gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id AND is_account_closed = 0 AND is_dormant_account = 1
            JOIN gaming_clients_login_attempts_totals ON gaming_clients_login_attempts_totals.client_id = gaming_clients.client_id
            LEFT JOIN gaming_player_statuses gps ON gaming_clients.player_status_id = gps.player_status_id
            LEFT JOIN gaming_player_statuses gpsc ON accountClosedStatusID = gpsc.player_status_id
    SET 
       -- Close Accounts
              is_account_closed = 1,
              account_closed_date =  NOW(),
              gaming_clients.player_status_id = IF(attributeAccountClosedIsFirstAndOnlyAttribute, accountClosedStatusID, gaming_clients.player_status_id),
              last_updated = IF((@playerAttributesAudits := AuditLogNewGroup(0, NULL, gaming_clients.client_id, 1, 'System' , NULL, NULL, gaming_clients.client_id)) != 0, last_updated, last_updated),
              last_updated = IF((@result := AuditLogAttributeChangeFunc('Is Account Closed', gaming_clients.client_id, @playerAttributesAudits, 'YES', 'NO', NOW())) != 0, last_updated, last_updated),
              last_updated = IF(attributeAccountClosedIsFirstAndOnlyAttribute AND (@playerStatusAudits := AuditLogNewGroup(0, NULL, gaming_clients.client_id, 12, 'System' , NULL, NULL, gaming_clients.client_id)) != 0, last_updated, last_updated),
              last_updated = IF(attributeAccountClosedIsFirstAndOnlyAttribute AND (@result := AuditLogAttributeChangeFunc('Player Status Changed', gaming_clients.client_id, @playerStatusAudits, gpsc.player_status_name, gps.player_status_name, NOW())) != 0, last_updated, last_updated)

    WHERE 
              (kyc_checked_status_id IS NULL OR kyc_checked_status_id NOT IN (IFNULL(KYCCheckedPlayerSelection, -1))) AND 
              gaming_clients.account_activated NOT IN (IFNULL(PlayerActivationSelected, -1)) AND 
              TIMESTAMPDIFF(DAY, IFNULL(last_dormant_date, NOW()), NOW()) >= DaysOfBeingTaggedDormant;   

         ELSE 
                      OPEN dormantCursor;    
                      dormantLoop : LOOP    
              		      SET notMoreRows = 0;        
                        FETCH dormantCursor INTO clientID;
              
                        	IF notMoreRows THEN
              			        LEAVE dormantLoop;
                          END IF;

                         UPDATE gaming_clients
                             SET 
                               -- Close Accounts
                              is_account_closed = IF(AccountClosureType = 'closed', 1, is_account_closed),
                              account_closed_date = IF(AccountClosureType = 'closed', NOW(), account_closed_date),                                
                              last_updated = IF(AccountClosureType = 'closed' AND (@playerAttributesAudits := AuditLogNewGroup(0, NULL, clientID, 1, 'System' , NULL, NULL, clientID)) != 0, last_updated, last_updated),
                              last_updated = IF(AccountClosureType = 'closed' AND (@result := AuditLogAttributeChangeFunc('Is Account Closed', clientID, @playerAttributesAudits, 'YES', 'NO', NOW())) != 0, last_updated, last_updated),
                              -- Disable players
                              gaming_clients.is_active = IF(AccountClosureType = 'inactive', 0, gaming_clients.is_active),
                              account_activated = IF(AccountClosureType = 'inactive', 0, gaming_clients.account_activated),
                              last_updated = IF(AccountClosureType = 'inactive' AND (@playerAttributesAudits := AuditLogNewGroup(0, NULL, clientID, 1, 'System' , NULL, NULL, clientID)) != 0, last_updated, last_updated),
                              last_updated = IF(AccountClosureType = 'inactive' AND (@result := AuditLogAttributeChangeFunc('Is Active', clientID, @playerAttributesAudits, 'NO', 'YES', NOW())) != 0, last_updated, last_updated)
                              WHERE gaming_clients.client_id = clientID;                       
    
                          CALL PlayerUpdatePlayerStatus(clientID);
    
								 
                       END LOOP;
        END IF;


  END IF;




  -- Clear Any Balances for closed accounts
  IF ClearAnyRemainingBalance THEN

    INSERT INTO gaming_transaction_counter_amounts 
      (
        transaction_counter_id, 
        client_stat_id, 
        amount
      ) 
    SELECT 
      CounterID,
      client_stat_id,
      current_real_balance * -1 AS fee  
    FROM gaming_clients
    JOIN gaming_client_stats 
      ON gaming_clients.client_id = gaming_client_stats.client_id 
       AND current_real_balance > 0
    JOIN gaming_payment_amounts
      ON gaming_client_stats.currency_id = gaming_payment_amounts.currency_id
        AND is_account_closed
        AND TIMESTAMPDIFF(DAY, IFNULL(account_closed_date, NOW()), NOW()) >= DaysOfAccountClosure 
    ON DUPLICATE KEY UPDATE
      amount = current_real_balance * -1;

    -- Forfeit all bonses for players
    INSERT INTO gaming_bonus_lost_counter (date_created)
    VALUES (NOW());

    SET BonusCounterID = LAST_INSERT_ID();

    INSERT INTO gaming_bonus_lost_counter_bonus_instances
      (
        bonus_lost_counter_id, 
        bonus_instance_id
      )
    SELECT 
      BonusCounterID, 
      bonus_instance_id
    FROM gaming_bonus_instances
    JOIN gaming_client_stats
      ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
    JOIN gaming_clients
      ON gaming_client_stats.client_id = gaming_clients.client_id
        AND is_account_closed
        AND TIMESTAMPDIFF(DAY, IFNULL(account_closed_date, NOW()), NOW()) >= DaysOfAccountClosure    
    WHERE NOT is_lost;

    CALL BonusForfeitBulk(0, BonusCounterID);
    
    DELETE FROM gaming_bonus_lost_counter_bonus_instances WHERE bonus_lost_counter_id = BonusCounterID;

  END IF;

  -- Update the player balances.
	UPDATE gaming_client_stats
	JOIN gaming_transaction_counter_amounts 
	ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id 
	  AND transaction_counter_id = CounterID
	SET 
	current_real_balance = current_real_balance + gaming_transaction_counter_amounts.amount, 
	total_inactivity_charges = total_inactivity_charges - gaming_transaction_counter_amounts.amount,
		last_inactive_fee_date = CurTimeStamp;

  -- Create Transaction
	INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id, gaming_transaction_counter_amounts.amount, ROUND(gaming_transaction_counter_amounts.amount/exchange_rate,5), gaming_client_stats.currency_id, exchange_rate, gaming_transaction_counter_amounts.amount, 0, 0, 0, CurTimeStamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 0, 0, 'Inactivity Fee', pending_bets_real, pending_bets_bonus,CounterID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_transaction_counter_amounts
	JOIN gaming_client_stats ON gaming_transaction_counter_amounts.client_stat_id = gaming_client_stats.client_stat_id
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'InactivityFee'
	JOIN gaming_operators ON is_main_operator
	JOIN gaming_operator_currency ON gaming_operator_currency.operator_id = gaming_operators.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id
	WHERE transaction_counter_id = CounterID;

  -- Add Game Plays
	SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

	INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,1,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
	FROM gaming_transactions
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'InactivityFee' AND gaming_transactions.transaction_counter_id = CounterID
	JOIN gaming_transaction_counter_amounts ON gaming_transactions.client_stat_id =gaming_transaction_counter_amounts.client_stat_id AND gaming_transaction_counter_amounts.transaction_counter_id = CounterID;

	SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);
   
  INSERT INTO 	gaming_game_play_ring_fenced 
				(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
  SELECT 		game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
  FROM			gaming_client_stats
				JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
					AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
  ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);

	DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id = CounterID;

END root$$

DELIMITER ;

