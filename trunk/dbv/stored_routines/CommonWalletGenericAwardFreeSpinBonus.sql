DROP procedure IF EXISTS `CommonWalletGenericAwardFreeSpinBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGenericAwardFreeSpinBonus`(gameManufacturerName VARCHAR(80), clientStatID BIGINT, bonusAmount DECIMAL(18, 5), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), amountCurrency CHAR(3), transactionComment TEXT, OUT statusCode INT)
root: BEGIN
  /* Status Codes 
   1654 - Bonus Is Disabled
   224 - Invalid or Inactive Player
   1655 - Player is not in bonus' player selection
   1637 - Bonus Amount not in range
   1614 - Invalid expiry days.
   1592 - Bonus not yet active.
   */  
   
   DECLARE startTime DATETIME DEFAULT NULL;
   DECLARE gamePlayIDReturned, bonusInstanceId BIGINT(20) DEFAULT NULL;
   DECLARE bonusInstanceComment VARCHAR(50) DEFAULT NULL;
   DECLARE bonusPreAuth, isAlreadyProcessed TINYINT(1) DEFAULT 0;
   DECLARE cwTransactionID BIGINT DEFAULT NULL;
      
   SELECT NOW() INTO startTime;
   
	CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, 'BonusAwarded', cwTransactionID, isAlreadyProcessed, statusCode);
	IF (isAlreadyProcessed) THEN
		LEAVE root;
	END IF;

   CALL BonusGivePlayerFreeSpinBonusByRuleID(0, 0, clientStatID, bonusAmount, NULL, NULL, NULL, bonusInstanceId, statusCode);

	-- SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
	-- IF (bonusPreAuth=0) THEN
		SELECT gaming_game_plays.game_play_id INTO gamePlayIDReturned
		FROM gaming_bonus_instances
		JOIN gaming_transactions ON gaming_transactions.extra_id = gaming_bonus_instances.bonus_instance_id
		JOIN gaming_game_plays ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id and gaming_payment_transaction_type.name = 'BonusAwarded'
		WHERE gaming_bonus_instances.client_stat_id = clientStatID AND gaming_bonus_instances.bonus_instance_id = bonusInstanceId LIMIT 1;
		
		SET bonusInstanceComment = CONCAT('bonus_instance_id: ', CAST(bonusInstanceId AS CHAR));
	-- ELSE Does not make sense to have pre-auth since player has played the free spins already.;
	-- END IF;
    
    IF (IFNULL(gameRef,'')='') THEN
		SELECT gaming_games.manufacturer_game_idf INTO gameRef
		FROM gaming_game_sessions FORCE INDEX (client_open_sessions) 
		JOIN gaming_games ON gaming_game_sessions.game_id=gaming_games.game_id
		WHERE gaming_game_sessions.client_stat_id=clientStatID AND gaming_game_sessions.is_open
		ORDER BY gaming_game_sessions.game_session_id DESC LIMIT 1;
    END IF;
    
	INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`, other_data, is_success, status_code, manual_update, currency_code)
	SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, bonusAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), CONCAT_WS(',', bonusInstanceComment, transactionComment), statusCode=0, statusCode, 0, amountCurrency 
	FROM gaming_payment_transaction_type AS transaction_type
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name = gameManufacturerName
	WHERE transaction_type.name='BonusAwarded';
	
	SET cwTransactionID=LAST_INSERT_ID(); 
  
	CALL CommonWalletPlayReturnData(cwTransactionID);
	SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
    
END root$$

DELIMITER ;

