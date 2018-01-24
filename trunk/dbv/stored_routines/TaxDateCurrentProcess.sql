DROP procedure IF EXISTS `TaxDateCurrentProcess`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TaxDateCurrentProcess`()
BEGIN
	#There should be only one current country tax rule (in gaming_country_tax) with the same country id and same license type.
	DECLARE varDone, currentSetStatus, countryReady INT DEFAULT 0;
    DECLARE currentTime, dateStart, dateEnd, creationDate DATETIME;
	DECLARE countryTaxId, countryId, licenceTypeId, isCurrent, countryIdPrevious, previousCountry, licenceTypePrevious, CounterID, previousCurrent BIGINT DEFAULT 0;
    DECLARE isActive TINYINT DEFAULT 0;
	DECLARE CurTimeStamp DATETIME;
	DECLARE taxCursor CURSOR FOR SELECT DISTINCT country_tax_id, country_id, licence_type_id, date_start, date_end, is_current, creation_date, is_active FROM gaming_country_tax ORDER BY country_id, licence_type_id, date_start DESC;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET varDone = 1;
             
	OPEN taxCursor;
	allCountriesLabel: LOOP 
		SET varDone=0;
		FETCH taxCursor INTO countryTaxId, countryId, licenceTypeId, dateStart, dateEnd, isCurrent, creationDate, isActive;
		IF (varDone) THEN
		  LEAVE allCountriesLabel;
		END IF;
		SET currentSetStatus = 0;
		
		IF (previousCountry != countryId OR licenceTypePrevious != licenceTypeId) THEN
			SET previousCountry = countryId;
		    SET licenceTypePrevious = licenceTypeId;
			SET countryReady = 0;
		END IF;

		SET currentTime = NOW();
		
		IF (dateStart IS NULL AND countryReady = 0 AND isActive = 1) THEN  
			IF (dateEnd IS NULL) THEN
				SET currentSetStatus = 1;
				SET countryReady = 1;
			ELSEIF (dateEnd > currentTime) THEN
				SET currentSetStatus = 1;
				SET countryReady = 1;
			END IF;
	    ELSEIF (dateEnd IS NULL AND countryReady = 0 AND isActive = 1) THEN 
			IF (dateStart <= currentTime) THEN
				SET currentSetStatus = 1;
				SET countryReady = 1;
			END IF;
		ELSEIF (dateStart <= currentTime AND dateEnd > currentTime AND countryReady = 0 AND isActive = 1) THEN
			SET currentSetStatus = 1;
			SET countryReady = 1;
		ELSE 
			SET currentSetStatus = 0;
		END IF;
		
		UPDATE gaming_country_tax 
        SET is_current = currentSetStatus
        WHERE country_tax_id = countryTaxId;
        
        IF((currentSetStatus = 1 AND countryReady = 1) OR (isCurrent = 1 AND currentSetStatus = 0)) THEN        
			#Check which players were using the old tax rule set as current, close the respective cycle and create a new one with the new rule.          
			SET CurTimeStamp = NOW();

			INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
			SET CounterID = LAST_INSERT_ID();

			INSERT INTO gaming_transaction_counter_amounts (transaction_counter_id,client_stat_id,amount)
			SELECT CounterID, gaming_tax_cycles.client_stat_id, LEAST(current_real_balance,deferred_tax)* -1 AS fee 
			FROM gaming_clients
			JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id #AND current_real_balance > 0
			JOIN gaming_tax_cycles ON gaming_tax_cycles.client_stat_id = gaming_client_stats.client_stat_id AND gaming_tax_cycles.is_active = 1
      JOIN gaming_country_tax ON gaming_country_tax.country_tax_id = gaming_tax_cycles.country_tax_id
      JOIN gaming_countries as gc ON gaming_country_tax.country_id = gc.country_id
			WHERE ((gaming_tax_cycles.country_tax_id != countryTaxId AND currentSetStatus = 1 AND countryReady = 1) 
				OR (gaming_tax_cycles.country_tax_id = countryTaxId AND isCurrent = 1 AND currentSetStatus = 0)
        OR (gaming_tax_cycles.country_tax_id = countryTaxId AND currentSetStatus = 1 AND countryReady = 1 AND ((gc.casino_tax = 1 AND (licenceTypeId = 1)) OR (gc.sports_tax = 1 AND (licenceTypeId = 3)) OR (gc.poker_tax = 1 AND (licenceTypeId = 2))) = 0))
				AND gaming_country_tax.country_id = countryId 
        AND gaming_country_tax.licence_type_id = licenceTypeId;
            
			UPDATE gaming_client_stats
			JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = CounterID
			SET current_real_balance = current_real_balance + gaming_transaction_counter_amounts.amount,
			  total_tax_paid = total_tax_paid - gaming_transaction_counter_amounts.amount
			WHERE gaming_transaction_counter_amounts.amount < 0;

			UPDATE gaming_client_stats
			JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = CounterID
			SET deferred_tax = 0;
			  
			INSERT INTO gaming_transactions
			(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
			SELECT gaming_payment_transaction_type.payment_transaction_type_id, gaming_transaction_counter_amounts.amount, ROUND(gaming_transaction_counter_amounts.amount/exchange_rate,5), gaming_client_stats.currency_id, exchange_rate, gaming_transaction_counter_amounts.amount, 0, 0, 0, CurTimeStamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 0, 0, 'Deferred Tax', pending_bets_real, pending_bets_bonus,CounterID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
			FROM gaming_transaction_counter_amounts
			JOIN gaming_client_stats ON gaming_transaction_counter_amounts.client_stat_id = gaming_client_stats.client_stat_id
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'DeferredTaxRuleChange '
			JOIN gaming_operators ON is_main_operator
			JOIN gaming_operator_currency ON gaming_operator_currency.operator_id = gaming_operators.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id
			WHERE transaction_counter_id = CounterID AND gaming_transaction_counter_amounts.amount < 0;

			SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

			INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
			SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,1,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
			FROM gaming_transactions
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'DeferredTaxRuleChange' AND gaming_transactions.transaction_counter_id = CounterID
			JOIN gaming_transaction_counter_amounts ON gaming_transactions.client_stat_id =gaming_transaction_counter_amounts.client_stat_id AND gaming_transaction_counter_amounts.transaction_counter_id = CounterID
			WHERE gaming_transaction_counter_amounts.amount < 0;

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

			UPDATE gaming_tax_cycles
			JOIN gaming_transaction_counter_amounts ON gaming_transaction_counter_amounts.transaction_counter_id = CounterID AND gaming_tax_cycles.client_stat_id = gaming_transaction_counter_amounts.client_stat_id
			SET cycle_end_date = NOW(), is_active = 0, deferred_tax_amount = gaming_transaction_counter_amounts.amount, cycle_closed_on = 'Other'
			WHERE gaming_tax_cycles.is_active = 1;
			
      /*INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
			SELECT gaming_country_tax.country_tax_id, gaming_client_stats.client_stat_id, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = gaming_client_stats.client_stat_id)
			FROM gaming_country_tax
      JOIN gaming_countries as gc ON gaming_country_tax.country_id = gc.country_id
			JOIN clients_locations ON gaming_country_tax.country_id = clients_locations.country_id and clients_locations.is_active = 1
			JOIN gaming_client_stats ON gaming_client_stats.client_id = clients_locations.client_id AND gaming_client_stats.is_active = 1
			LEFT JOIN gaming_tax_cycles ON gaming_client_stats.client_stat_id = gaming_tax_cycles.client_stat_id 
				AND gaming_tax_cycles.country_tax_id = gaming_country_tax.country_tax_id
        AND gaming_tax_cycles.is_active = 1
      WHERE gaming_country_tax.country_tax_id = countryTaxId       
        AND gaming_country_tax.licence_type_id = licenceTypeId
        AND gaming_country_tax.is_active = 1
		AND gaming_country_tax.is_current = 1
		AND tax_cycle_id is null
        AND ((gc.casino_tax = 1 AND (licenceTypeId = 1)) OR (gc.sports_tax = 1 AND (licenceTypeId = 3)) OR (gc.poker_tax = 1 AND (licenceTypeId = 2)));*/
            
            DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id = CounterID;        
		END IF;

		COMMIT AND CHAIN;
	END LOOP allCountriesLabel;
	CLOSE taxCursor;	
		
END$$

DELIMITER ;