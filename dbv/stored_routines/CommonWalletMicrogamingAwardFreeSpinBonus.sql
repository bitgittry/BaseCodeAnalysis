DROP procedure IF EXISTS `CommonWalletMicrogamingAwardFreeSpinBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletMicrogamingAwardFreeSpinBonus`(clientStatID BIGINT, bonusAmount DECIMAL(18, 5), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), amountCurrency CHAR(3), transactionComment TEXT, OUT statusCode INT)
root: BEGIN
   
   
   DECLARE startTime DATETIME DEFAULT NULL;
   DECLARE gamePlayIDReturned, bonusInstanceId BIGINT(20) DEFAULT NULL;
   DECLARE bonusInstanceComment VARCHAR(50) DEFAULT NULL;
   DECLARE bonusPreAuth, isAlreadyProcessed TINYINT(1) DEFAULT 0;
   DECLARE cwTransactionID BIGINT DEFAULT NULL;
      
   SELECT NOW() INTO startTime;
   
	CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, 'Microgaming', 'BonusAwarded', cwTransactionID, isAlreadyProcessed, statusCode);
	IF (isAlreadyProcessed) THEN
		LEAVE root;
	END IF;

   CALL BonusGivePlayerFreeSpinBonusByRuleID(0, 0, clientStatID, bonusAmount, NULL, NULL, NULL, bonusInstanceId, statusCode);

	IF (statusCode <> 0) THEN
		LEAVE root;
	END IF;
  
	
  
	
		SELECT gaming_game_plays.game_play_id INTO gamePlayIDReturned
		FROM gaming_bonus_instances
		JOIN gaming_transactions ON gaming_transactions.extra_id = gaming_bonus_instances.bonus_instance_id
		JOIN gaming_game_plays ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id and gaming_payment_transaction_type.name = 'BonusAwarded'
		WHERE gaming_bonus_instances.client_stat_id = clientStatID AND gaming_bonus_instances.bonus_instance_id = bonusInstanceId LIMIT 1;
		
		SET bonusInstanceComment = CONCAT('bonus_instance_id: ', CAST(bonusInstanceId AS CHAR));
	
	
	
	INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`, other_data, is_success, status_code, manual_update, currency_code)
	SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, bonusAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), CONCAT_WS(',', bonusInstanceComment, transactionComment), statusCode=0, statusCode, 0, amountCurrency 
	FROM gaming_payment_transaction_type AS transaction_type
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name = 'Microgaming'
	WHERE transaction_type.name='BonusAwarded';
	
	SET cwTransactionID=LAST_INSERT_ID(); 
  
	CALL CommonWalletPlayReturnData(cwTransactionID);
	SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
END root$$

DELIMITER ;

