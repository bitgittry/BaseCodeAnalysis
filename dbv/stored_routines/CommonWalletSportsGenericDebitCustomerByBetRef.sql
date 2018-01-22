DROP procedure IF EXISTS `CommonWalletSportsGenericDebitCustomerByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericDebitCustomerByBetRef`(
  gameManufacturerID BIGINT, transactionRef VARCHAR(100), betTransactionRef VARCHAR(80), betRef VARCHAR(40), debitAmount DECIMAL(18,5), 
  minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN

  -- First Version
  -- Close Round: 0

  SET gamePlayIDReturned = NULL;
  CALL CommonWalletSportsGenericCreditCustomerByBetRef(gameManufacturerID, transactionRef, 
	betTransactionRef, betRef, ABS(debitAmount)*-1, 1, 0, 0, minimalData, gamePlayIDReturned, statusCode);

END$$

DELIMITER ;

