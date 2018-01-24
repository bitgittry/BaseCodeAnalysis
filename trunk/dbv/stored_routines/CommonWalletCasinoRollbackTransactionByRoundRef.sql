DROP procedure IF EXISTS `CommonWalletCasinoRollbackTransactionByRoundRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCasinoRollbackTransactionByRoundRef`(
  extTransactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), roundRef BIGINT, clientStatID VARCHAR(80),
  transactionType VARCHAR(80), txComment TEXT, minimalData TINYINT(1), OUT statusCode INT, OUT thisTransId BIGINT)
root: BEGIN

	

	DECLARE cwTransactionID BIGINT DEFAULT NULL;
	
	SET thisTransId=NULL;
	
	IF(ISNULL(extTransactionRef) || ISNULL(gameManufacturerName) || ISNULL(roundRef) || ISNULL(clientStatID)) THEN
		SET statusCode = 205  ;
		LEAVE root;
	END IF;

	SELECT gct.cw_transaction_id INTO cwTransactionId
	FROM gaming_cw_transactions gct 
	JOIN gaming_payment_transaction_type gpt 
		ON gpt.payment_transaction_type_id = gct.payment_transaction_type_id AND (gpt.name = transactionType OR transactionType IS NULL)
	WHERE gct.round_ref = roundRef AND gct.client_stat_id = clientStatID
	ORDER BY cw_transaction_id DESC LIMIT 1;
	
	IF(ISNULL(cwTransactionID)) THEN
		SET statusCode = 1023;
		LEAVE root;
	END IF;
	
	CALL CommonWalletCasinoRollbackTransaction(cwTransactionId, extTransactionRef, txComment, minimalData, statusCode, thisTransId);

END root$$

DELIMITER ;

