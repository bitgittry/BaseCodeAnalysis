DROP function IF EXISTS `GetBoolGamingSetting`;

DELIMITER $$
CREATE DEFINER=`root`@`localhost` FUNCTION `GetBoolGamingSetting`(setting_name VARCHAR(80)) RETURNS tinyint(1)
BEGIN
  SELECT value_bool INTO @valueBool FROM gaming_settings WHERE name='COUNTRY_COMPILED_ADDRESS_ENABLED';
  RETURN @valueBool;
END$$

DELIMITER ;

