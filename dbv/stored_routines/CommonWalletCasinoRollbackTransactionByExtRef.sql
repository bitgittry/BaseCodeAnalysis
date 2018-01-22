DROP procedure IF EXISTS `CommonWalletCasinoRollbackTransactionByExtRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCasinoRollbackTransactionByExtRef`(
  extTransactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), transactionToRollbackExtRef VARCHAR(80), 
  transactionType VARCHAR(80), txComment TEXT, minimalData TINYINT(1), OUT statusCode INT, OUT thisTransId BIGINT)
root: BEGIN

	DECLARE cwTransactionID BIGINT DEFAULT NULL;
	
	SET thisTransId=NULL;
	
	IF(ISNULL(extTransactionRef) || ISNULL(gameManufacturerName) || ISNULL(transactionToRollbackExtRef)) THEN
		SET statusCode = 205;
		LEAVE root;
	END IF;
	
	SELECT gaming_cw_transactions.cw_transaction_id INTO cwTransactionID
	FROM gaming_cw_transactions
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.`name`=gameManufacturerName
		AND gaming_cw_transactions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id 
		AND (gaming_game_manufacturers.tran_ref_reset_date IS NULL OR gaming_cw_transactions.`timestamp`>=gaming_game_manufacturers.tran_ref_reset_date)
	JOIN gaming_payment_transaction_type ON gaming_cw_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
	WHERE IF(transactionType IS NULL, gaming_payment_transaction_type.`name` IN ('Bet', 'Win', 'BonusAwarded'), transactionType = gaming_payment_transaction_type.`name`)
		AND gaming_cw_transactions.transaction_ref=transactionToRollbackExtRef 
	ORDER BY gaming_cw_transactions.cw_transaction_id DESC LIMIT 1;

	IF(ISNULL(cwTransactionID)) THEN
		SET statusCode = 1023;
		LEAVE root;
	END IF;

	CALL CommonWalletCasinoRollbackTransaction(cwTransactionId, extTransactionRef, txComment, minimalData, statusCode, thisTransId);

END root$$

DELIMITER ;

