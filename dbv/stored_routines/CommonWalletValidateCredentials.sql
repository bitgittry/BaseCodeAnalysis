DROP function IF EXISTS `CommonWalletValidateCredentials`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CommonWalletValidateCredentials`(gameManufacturerName VARCHAR(80), apiUsername VARCHAR(80), apiPassword VARCHAR(80)) RETURNS tinyint(1)
root: BEGIN
  DECLARE gameManufacturerID BIGINT DEFAULT -1;
  DECLARE dbApiUsername, dbApiPassword, hashedPassword VARCHAR(1024);
  SELECT game_manufacturer_id INTO gameManufacturerID FROM gaming_game_manufacturers WHERE name=gameManufacturerName;
  SELECT attr_value INTO dbApiUsername FROM gaming_game_manufacturer_attributes WHERE game_manufacturer_id=gameManufacturerID AND attr_name='api_username'; 
  SELECT attr_value INTO dbApiPassword FROM gaming_game_manufacturer_attributes WHERE game_manufacturer_id=gameManufacturerID AND attr_name='api_password'; 
  
  IF (gameManufacturerID=-1) THEN
    RETURN 0;
  END IF;
  
  IF (COALESCE(apiUsername,'')!=COALESCE(dbApiUsername,'')) THEN
    RETURN 0;
  END IF;
  
  SET hashedPassword=SHA2(IFNULL(apiPassword,''),256);
  IF (hashedPassword <> dbApiPassword) THEN
    RETURN 0;
  END IF;
  RETURN 1;
END root$$

DELIMITER ;

