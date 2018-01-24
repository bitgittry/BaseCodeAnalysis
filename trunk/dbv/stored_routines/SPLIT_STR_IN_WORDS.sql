DROP function IF EXISTS `SPLIT_STR_IN_WORDS`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `SPLIT_STR_IN_WORDS`(toSplit VARCHAR(250), everyNChar INT, delim VARCHAR(2)) RETURNS varchar(255) CHARSET utf8
BEGIN
 
  DECLARE retString VARCHAR(255) DEFAULT '';
  DECLARE toSplitLength INT DEFAULT CHAR_LENGTH(IFNULL(toSplit,''));
  DECLARE charCount INT DEFAULT 0;

  IF (toSplitLength=0 OR toSplitLength<=everyNChar) THEN
	RETURN toSplit;
  END IF;

  label1: LOOP
	SET retString = CONCAT(retString, SUBSTR(toSplit, charCount + 1, everyNChar),
		IF (charCount + everyNChar < toSplitLength, delim, ''));
  
    SET charCount = charCount + everyNChar;
    
	IF charCount < toSplitLength THEN
      ITERATE label1;
    END IF;
  
    LEAVE label1;
  END LOOP label1;

  RETURN retString;
  
END$$

DELIMITER ;

