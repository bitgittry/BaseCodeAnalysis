DROP procedure IF EXISTS `GameManufacturerAttributeSave`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameManufacturerAttributeSave`(gameManufacturerID BIGINT, attrName VARCHAR(200), attrValue VARCHAR(16384))
BEGIN
  SELECT CASE attrName
    WHEN 'api_password' THEN SHA2(attrValue,256)
    ELSE attrValue
  END INTO attrValue;
  INSERT INTO gaming_game_manufacturer_attributes (game_manufacturer_id, attr_name, attr_value) VALUES (gameManufacturerID, attrName, attrValue) 
  ON DUPLICATE KEY UPDATE attr_value=attrValue; 
END$$

DELIMITER ;

