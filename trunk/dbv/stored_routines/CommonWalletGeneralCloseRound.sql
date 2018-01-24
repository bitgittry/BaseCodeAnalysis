DROP procedure IF EXISTS `CommonWalletGeneralCloseRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGeneralCloseRound`(roundRef BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80))
root:BEGIN
  
  DECLARE gameManufacturerID BIGINT DEFAULT -1; 
  
  SELECT game_manufacturer_id INTO gameManufacturerID FROM gaming_game_manufacturers WHERE gaming_game_manufacturers.name=gameManufacturerName; 
  
  CALL CommonWalletCloseRound(roundRef, gameManufacturerID, clientStatID); 
 
END root$$

DELIMITER ;

