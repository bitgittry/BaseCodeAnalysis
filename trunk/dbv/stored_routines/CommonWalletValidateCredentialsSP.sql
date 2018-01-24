DROP procedure IF EXISTS `CommonWalletValidateCredentialsSP`;

DELIMITER $$
CREATE DEFINER=`dba_stever`@`%` PROCEDURE `CommonWalletValidateCredentialsSP`(gameManufacturerName VARCHAR(80), apiUsername VARCHAR(80), apiPassword VARCHAR(80), OUT statusCode INT)
BEGIN

	SELECT CommonWalletValidateCredentials(gameManufacturerName, apiUsername, apiPassword) INTO statusCode;
END$$

DELIMITER ;

