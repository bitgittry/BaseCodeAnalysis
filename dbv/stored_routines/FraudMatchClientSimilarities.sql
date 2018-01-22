DROP procedure IF EXISTS `FraudMatchClientSimilarities`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudMatchClientSimilarities`(clientID BIGINT)
BEGIN
  
  SET @rowCount=0;
  
  CALL FraudMatchClientName(clientID, @rowCount);
  CALL FraudMatchClientDetails(clientID, @rowCount);
  CALL FraudMatchClientAddress(clientID, @rowCount);
   
END$$

DELIMITER ;

