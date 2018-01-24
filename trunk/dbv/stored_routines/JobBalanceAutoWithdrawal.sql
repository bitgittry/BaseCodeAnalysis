DROP procedure IF EXISTS `JobBalanceAutoWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `JobBalanceAutoWithdrawal`(jobRunID BIGINT)
root: BEGIN
	-- CPREQ-36

  DECLARE v_jobName VARCHAR(50) DEFAULT 'JobBalanceAutoWithdrawal';
	DECLARE v_maximumPlayerEwalletBalanceThresholdEnabled TINYINT(1) DEFAULT 0;
  DECLARE v_playersBlockSizeDefault INT DEFAULT 10000; -- or ~0 >> 33 MAX INTEGER SIGNED
	DECLARE v_playersBlockSize INT;
	DECLARE v_finished INT DEFAULT 0;
	DECLARE v_statusCode INT DEFAULT 0;
    
  DECLARE v_clientStatID BIGINT;
  DECLARE v_maxBalanceThreshold DECIMAL(18, 5);
  DECLARE v_maxBalanceThresholdCountry DECIMAL(18, 5);
  DECLARE v_countryCode VARCHAR(2);
  DECLARE v_currentRealBalance DECIMAL(18, 5);
  DECLARE v_balanceAccountID, v_currentRegType BIGINT;
  DECLARE v_canWithdraw, v_FullRigisteredWithrawWithCheque TINYINT(1) DEFAULT 0;
  DECLARE v_varAmount DECIMAL(18, 5);

    
	DECLARE v_playersCursor CURSOR FOR 
		SELECT gaming_client_stats.client_stat_id, gaming_client_stats.max_player_balance_threshold, 
      gaming_countries.country_code, gaming_countries.max_player_balance_threshold AS max_player_balance_threshold_country,
      gaming_client_stats.current_real_balance,gcr.client_registration_type_id
		FROM gaming_client_stats FORCE INDEX (balance_last_change_date)
		STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id 
        STRAIGHT_JOIN gaming_client_registrations gcr ON gaming_clients.client_id = gcr.client_id AND gcr.is_current = 1
		LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary = 1
		LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id 
		WHERE 
			  gaming_client_stats.is_active = 1 AND			 
			  gaming_client_stats.current_real_balance > LEAST(gaming_client_stats.max_player_balance_threshold, gaming_countries.max_player_balance_threshold) AND
              gaming_clients.is_account_closed=0
		LIMIT v_playersBlockSize;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_finished = 1;

	SELECT value_bool INTO v_maximumPlayerEwalletBalanceThresholdEnabled FROM gaming_settings WHERE `name`='MAXIMUM_PLAYER_EWALLET_BALANCE_THRESHOLD_ENABLED';

	IF (1 = v_maximumPlayerEwalletBalanceThresholdEnabled) THEN
    
		SELECT value_int INTO v_playersBlockSize FROM gaming_settings WHERE `name`='JOB_BALANCE_AUTO_WITHDRAWAL_PLAYERS_BLOCK_SIZE';
        SELECT value_bool INTO v_FullRigisteredWithrawWithCheque FROM gaming_settings WHERE `name`='AUTO_WITHDRAW_FULL_PLAYER_WITH_CHEQUE';
		
        SET v_playersBlockSize = ifnull(v_playersBlockSize, v_playersBlockSizeDefault);
    
		OPEN v_playersCursor;

		balance_auto_withdraw: LOOP
			SET v_finished = 0;

			FETCH v_playersCursor INTO v_clientStatID, v_maxBalanceThreshold, 
				v_countryCode, v_maxBalanceThresholdCountry,
				v_currentRealBalance, v_currentRegType;

			IF (1 = v_finished) THEN
				LEAVE balance_auto_withdraw;
			END IF;

			-- Balance Account Default
			-- \_ Payment Method Default
			--    \_ Balance Account link to Operator Payment default

			-- // Get Default Withdrawal Balance Account ID and related Payment Method ID
		SELECT gaming_balance_accounts.balance_account_id -- , gaming_balance_accounts.can_withdraw, gaming_balance_accounts.payment_method_id 
		INTO v_balanceAccountID -- , v_canWithdraw, v_paymentMethodID 
		FROM gaming_balance_accounts 
		JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_accounts.payment_method_id AND gaming_payment_method.can_withdraw = 1 AND gaming_payment_method.is_active = 1
		WHERE client_stat_id = v_clientStatID AND gaming_balance_accounts.is_active = 1 AND gaming_balance_accounts.is_default_withdrawal = 1; 

		IF(v_currentRegType=3 AND v_FullRigisteredWithrawWithCheque=0 AND v_balanceAccountID IS NULL) THEN
			SET v_statusCode = 19; -- do not allow full registered player to withdraw if they do not have a bank account
        END IF;
            

		IF (v_balanceAccountID IS NULL AND v_statusCode=0) THEN
			-- Defaulted to Cheque
			SELECT balance_account_id, can_withdraw INTO v_balanceAccountID, v_canWithdraw
			FROM gaming_balance_accounts 
			WHERE client_stat_id = v_clientStatID AND payment_method_id = 20;	
            
			IF (v_balanceAccountID IS NULL) THEN
				-- Insert New Balance Account (Cheque)
				INSERT INTO gaming_balance_accounts (date_created, date_last_used, client_stat_id, payment_method_id, payment_gateway_id, sub_payment_method_id, is_internal, can_withdraw)
				VALUES(NOW(), NOW(), v_clientStatID, 20, 5, 20, 1, 1);
				
				SET v_balanceAccountID = LAST_INSERT_ID();
			ELSEIF (v_canWithdraw = 0) THEN
				UPDATE gaming_balance_accounts SET can_withdraw = 1
				WHERE balance_account_id = v_balanceAccountID;
			END IF;
	
		END IF;          

			START TRANSACTION;

        IF (0 = v_statusCode) THEN
          SET v_varAmount = v_currentRealBalance - ifnull(LEAST(v_maxBalanceThreshold, v_maxBalanceThresholdCountry), v_currentRealBalance);
		  SET v_varAmount = LEAST(v_varAmount,CalculateWithdrawableAmount(v_clientStatID));
		 
		    -- Check amount is not 0
			IF (v_varAmount > 0) THEN   		           
			  CALL TransactionQueueWithdrawal(
				0 					 		    /*sessionID*/ , 
				v_clientStatID 	 		/*clientStatID*/ , 
				v_balanceAccountID 	/*balanceAccountID*/ , 
				v_varAmount		 			/*varAmount*/ , 
				'Auto-withdrawal due maximum player ewallet balance over threshold' /*varReason*/ , 
				0 					 		    /*isCashback*/ , 
				1								/*charge*/,
				0 					 		    /*requestedByUser*/ , 
				null 				 		    /*paymentKey*/ , 
				null 				 		    /*newAccountReference*/ , 
				'Auto-Withdrawal' 	/*issueWithdrawalType*/ ,
				null,
				1 					 		    /*ignoreWithdrawalChecks*/ ,
				v_statusCode 		 		/*statudCode*/ );
			ELSE
			  -- 18 - Withdrawal amount is < 0
			  SET v_statusCode = 18; 
			END IF;

        END IF;

        -- // In case of error exclude player from next execution and track error
		-- // If withdraw amount is <= 0 then do not log - it is not an error
        IF (0 <> v_statusCode AND v_statusCode != 18) THEN
           INSERT INTO gaming_job_run_errors (job_run_id, client_stat_id, status_code) VALUES (jobRunID, v_clientStatID, v_statusCode);
        END IF;

        SET @notificationTypeID = IF (0 = v_statusCode, 603 /*AutoWithdrawInitiated*/ , 604 /*AutoWithdrawalFailed*/ );
		IF (v_balanceAccountID IS NOT NULL) THEN
			CALL NotificationEventCreate(@notificationTypeID, v_clientStatID, v_balanceAccountID, 0);
		END IF;

		COMMIT;
		
		/* Fix in order to continue withdrawals even if one fails */
		SET v_statusCode = 0;
		
		END LOOP balance_auto_withdraw;

		CLOSE v_playersCursor;
	END IF;
END root$$

DELIMITER ;

