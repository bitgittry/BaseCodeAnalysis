 
DROP function IF EXISTS `PadPlayerCard`;

DELIMITER $$
 
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PadPlayerCard`(cardId bigint(20)) RETURNS varchar(256) CHARSET utf8
BEGIN
	
    DECLARE digitsNumber int(11);
	SELECT value_int INTO  digitsNumber FROM gaming_settings WHERE name='PLAYERCARD_DIGITS_NUMBER' ;
    RETURN  LPAD(cardId, digitsNumber, '0');
  
END$$

DELIMITER ;

