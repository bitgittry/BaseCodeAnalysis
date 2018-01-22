DROP function IF EXISTS `SanitizeFullTextSearchInput`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` FUNCTION `SanitizeFullTextSearchInput`(input NVARCHAR(1024), replaceCharacter CHAR(1)) RETURNS varchar(1024) CHARSET utf8
BEGIN
  DECLARE sanitizedInput NVARCHAR(1024);
  DECLARE tempReplaceCharacter CHAR(1);
  
  SET sanitizedInput = input;
  SET tempReplaceCharacter = '';
  
  IF (replaceCharacter IS NOT NULL OR replaceCharacter <> '') THEN 
    SET tempReplaceCharacter = replaceCharacter;
  END IF;

  SET sanitizedInput = REPLACE(sanitizedInput,'(',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,')',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'*',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'+',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'-',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'<',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'>',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'@',tempReplaceCharacter);
  SET sanitizedInput = REPLACE(sanitizedInput,'~',tempReplaceCharacter);

  RETURN  sanitizedInput;
END$$

DELIMITER ;

