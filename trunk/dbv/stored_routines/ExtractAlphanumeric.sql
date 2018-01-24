DROP function IF EXISTS `ExtractAlphanumeric`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `ExtractAlphanumeric`(str VARCHAR(250), stripNumbers TINYINT(1)) RETURNS varchar(255) CHARSET utf8
BEGIN 
  DECLARE i, len SMALLINT DEFAULT 1; 
  DECLARE ret VARCHAR(255);
  DECLARE pattern VARCHAR(16);
  DECLARE c CHAR(1); 
  
  IF (str IS NOT NULL) THEN
	  SET len = CHAR_LENGTH( str );
      SET ret = '';
	  SET pattern = IF(stripNumbers > 0, '[[:alpha:]]', '[[:alnum:]]' );   
	  REPEAT 
		BEGIN 
		  SET c = MID( str, i, 1 ); 
		  IF c REGEXP pattern THEN 
			SET ret=CONCAT(ret,c); 
		  END IF; 
		  SET i = i + 1; 
		END; 
	  UNTIL i > len END REPEAT; 
  END IF;
  
  RETURN ret; 
END$$

DELIMITER ;

