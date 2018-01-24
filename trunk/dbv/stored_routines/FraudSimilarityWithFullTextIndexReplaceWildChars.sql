DROP function IF EXISTS `FraudSimilarityWithFullTextIndexReplaceWildChars`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `FraudSimilarityWithFullTextIndexReplaceWildChars`(fullTextFilter VARCHAR(64)) RETURNS varchar(64) CHARSET utf8
BEGIN
	
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(fullTextFilter, '-*', '*'), '~*', '*'), '+*', '*'), '@*', '*'); 
    
END$$

DELIMITER ;

