DROP procedure IF EXISTS `CommonWalletCasinoRollbackTransaction`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCasinoRollbackTransaction`(
  cwTransactionId BIGINT, extTransactionRef VARCHAR(80), txComment TEXT, 
  minimalData TINYINT(1), OUT statusCode INT, OUT thisTransId BIGINT)
root: BEGIN

	/* 
		This SP makes use of OUT parameters to return state to the callers, 
		since when calling the roll-back SP's they return data which we're not interested in.
		
		StatusCodes:
		0		Successful
		205		Invalid Parameter
		1005	Already Processed
		1013	Unsupported request type
		1023	Transaction Not Found
		1028	Operation Failed
		1036	Roll-back failed because referenced transaction was unsuccessful

	*/

	DECLARE cwTranId, gamePlayID, gamePlayIDReturned, rollbackRef, clientStatId, bonusInstanceId, cwFreeRoundId, numFreeRoundsAwarded BIGINT DEFAULT NULL;
	DECLARE transTypeId, sessionID, gameSessionID, transactionRef, roundRef, currencyID, gameRoundID BIGINT DEFAULT NULL;
	DECLARE transType, gameManufacturerName, currencyCode VARCHAR(80) DEFAULT NULL; 
	DECLARE tranSuccessful TINYINT(1) DEFAULT 0; 
	DECLARE prevStatusCode INT DEFAULT -1; 
	DECLARE amountInPlayerCurrency, amountByGameManufacturer, amountCwFreeRoundWin DECIMAL DEFAULT 0;
	DECLARE thisPaymentTransType VARCHAR(80) DEFAULT NULL; 

	SET thisTransId=NULL;
	
	SELECT cw_transaction_id, client_stat_id, payment_transaction_type_id, is_success, status_code, gaming_cw_transactions.game_play_id, rollback_ref, amount, cw_free_round_id
	INTO cwTranId, clientStatId, transTypeId, tranSuccessful, prevStatusCode, gamePlayID, rollbackRef, amountByGameManufacturer, cwFreeRoundId
	FROM gaming_cw_transactions 
	LEFT JOIN gaming_game_plays_cw_free_rounds ON gaming_cw_transactions.game_play_id = gaming_game_plays_cw_free_rounds.game_play_id
    WHERE cw_transaction_id = cwTransactionId;

	IF(ISNULL(extTransactionRef) OR ISNULL(cwTransactionId)) THEN
		-- Invalid Parameter
		SET statusCode = 205; 
		LEAVE root;
	END IF;

	IF(ISNULL(cwTranId)) THEN
		SET statusCode = 1023; 
		LEAVE root;
	END IF;

	IF(!tranSuccessful OR prevStatusCode != 0) THEN
		SET statusCode = 1036; 
		LEAVE root;
	END IF;

	IF (rollbackRef IS NOT NULL) then
		SET thisTransId=rollbackRef;
		SET statusCode = 1005; 
		LEAVE root;
	END IF;
    
    SELECT client_stat_id INTO clientStatId FROM gaming_client_stats WHERE client_stat_id=clientStatId FOR UPDATE;

	SELECT `name` INTO transType
	FROM gaming_payment_transaction_type 
	WHERE gaming_payment_transaction_type.payment_transaction_type_id = transTypeId;

	CASE transType
		WHEN 'Bet' THEN
			BEGIN
				IF(!ISNULL(gamePlayID)) THEN
					SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
				
					SELECT gaming_game_plays.session_id, gaming_game_plays.game_session_id, gaming_game_plays.amount_total
						INTO sessionID, gameSessionID, amountInPlayerCurrency
						FROM gaming_game_plays 
						WHERE game_play_id=gamePlayID;

						IF (@wagerType='Type2') THEN
							CALL PlaceBetCancelTypeTwo(gamePlayID, sessionID, gameSessionID, amountInPlayerCurrency, extTransactionRef, 
								minimalData, gamePlayIDReturned, statusCode);
						ELSE
							CALL PlaceBetCancel(gamePlayID, sessionID, gameSessionID, amountInPlayerCurrency, extTransactionRef, 
								minimalData, gamePlayIDReturned, statusCode);
						END IF;
						
						SET thisPaymentTransType='BetCancelled';
						IF(statusCode <> 0) THEN
							SET statusCode = 1028;
							LEAVE root; 
						END IF;
				ELSE 
					-- If entry in gaming_cw_transaction does not have a game play id and transaction type is bet therefore original transaction had failed
					SET statusCode = 1036; 
					LEAVE root;
				END IF;

			END;
		WHEN 'BonusAwarded' THEN
			BEGIN

				IF (cwFreeRoundId IS NOT NULL) THEN
					SELECT gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays_cw_free_rounds.amount_free_round_win, 
						free_rounds_awarded, gaming_cw_transactions.transaction_ref, gaming_cw_transactions.round_ref, gaming_currency.currency_id, 
                        gaming_game_manufacturers.name, gaming_currency.currency_code
					INTO gameRoundID, clientStatId, amountCwFreeRoundWin, 
						numFreeRoundsAwarded, transactionRef, roundRef, currencyID, 
                        gameManufacturerName, currencyCode
					FROM gaming_game_plays				
					STRAIGHT_JOIN gaming_game_plays_cw_free_rounds ON gaming_game_plays.game_play_id = gaming_game_plays_cw_free_rounds.game_play_id
					STRAIGHT_JOIN gaming_cw_free_rounds ON gaming_game_plays_cw_free_rounds.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id					
					STRAIGHT_JOIN gaming_cw_transactions ON gaming_cw_transactions.game_play_id = gaming_game_plays_cw_free_rounds.game_play_id
					STRAIGHT_JOIN gaming_currency ON gaming_game_plays.currency_id = gaming_currency.currency_id
					STRAIGHT_JOIN gaming_game_manufacturers ON gaming_game_plays.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id	
					WHERE gaming_game_plays.game_play_id = gamePlayID;

					SELECT clientStatId, gamePlayID;					
					
                    CALL BonusExchangeRollBackFreeRounds(cwFreeRoundId, clientStatId, numFreeRoundsAwarded, roundRef, gameRoundID, 
						amountCwFreeRoundWin, transactionRef, gameManufacturerName, currencyCode, statusCode);
				ELSE 
					SELECT gaming_game_plays.client_stat_id, gaming_bonus_instances.bonus_instance_id, gaming_game_plays.amount_total
						INTO clientStatId, bonusInstanceId, amountInPlayerCurrency
					FROM gaming_game_plays 
					STRAIGHT_JOIN gaming_transactions ON 
						gaming_transactions.transaction_id=gaming_game_plays.transaction_id
					STRAIGHT_JOIN gaming_bonus_instances ON 
						gaming_bonus_instances.bonus_instance_id=gaming_transactions.extra_id
					STRAIGHT_JOIN gaming_payment_transaction_type ON 
						gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id
						AND gaming_payment_transaction_type.name = 'BonusAwarded'
					WHERE gaming_game_plays.game_play_id = gamePlayID;
						
					IF(ISNULL(clientStatId) OR ISNULL(bonusInstanceId)) THEN
						SET statusCode = 205; 
						LEAVE root;
					END IF;
						
					CALL BonusForfeitBonus(0, clientStatID, bonusInstanceId, 1, 'ForfeitByGameManufacturer', 'Rollback of Bonus awarding by Game Manufacturer');

					SET gamePlayIDReturned=@gamePlayIDFromOnLostBonus;

				END IF;
				
				SET thisPaymentTransType='ExternalBonusLost';
				
				IF(ISNULL(clientStatId)) THEN
					SET statusCode = 1028; 
					LEAVE root;
				END IF;
				
				SET statusCode = 0;
			END;
		ELSE
			BEGIN
				SET statusCode = 1013; 
				LEAVE root;
			END;
	END CASE;
 

	INSERT INTO gaming_cw_transactions (
		`game_manufacturer_id`, `payment_transaction_type_id`,  `client_stat_id`, `amount`, 
		`transaction_ref`, `game_ref`, `round_ref`, `game_play_id`, `is_success`, `timestamp`, `other_data`, `status_code`, 
		 `manual_update`, `currency_code`, `exchange_rate`,  `rollback_ref` )
		SELECT gaming_cw_transactions.game_manufacturer_id, transaction_type.payment_transaction_type_id, gaming_cw_transactions.client_stat_id, amountByGameManufacturer, 
			extTransactionRef, gaming_cw_transactions.game_ref, gaming_cw_transactions.round_ref, gamePlayIDReturned, IF(statusCode=0,1,0), NOW(), txComment, statusCode, 
			0, gaming_cw_transactions.currency_code, gaming_cw_transactions.exchange_rate, NULL
		FROM gaming_cw_transactions
		JOIN gaming_payment_transaction_type AS transaction_type ON transaction_type.`name`=thisPaymentTransType
		WHERE cw_transaction_id = cwTranId;
    
	SET thisTransId=LAST_INSERT_ID();

	UPDATE gaming_cw_transactions
	SET rollback_ref = thisTransId
	WHERE cw_transaction_id = cwTranId;

	SET statusCode = 0;
END root$$

DELIMITER ;

