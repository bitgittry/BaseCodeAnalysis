DROP procedure IF EXISTS `PlayerUpdatePlayerValidate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePlayerValidate`(clientID BIGINT, countryCode VARCHAR(3), languageCode VARCHAR(10), varEmail VARCHAR(80), varUsername VARCHAR(45), varNickname VARCHAR(60), varMob VARCHAR(45), clientSegmentID BIGINT, clientSecretQuestionID BIGINT)
BEGIN
  -- Returning current username   
    DECLARE usernameCaseSensitive TINYINT(1) DEFAULT 0;

	SELECT value_bool INTO usernameCaseSensitive FROM gaming_settings WHERE name='USERNAME_CASE_SENSITIVE';

  SELECT COUNT(*) INTO @numCountries FROM gaming_countries WHERE country_code=countryCode;
  SELECT COUNT(*) INTO @numLanguages FROM gaming_languages WHERE language_code=languageCode;
  SELECT COUNT(*) INTO @numEmail FROM gaming_clients WHERE email=varEmail AND client_id!=clientID AND is_account_closed=0; 
  SELECT COUNT(*) INTO @numUsername FROM gaming_clients FORCE INDEX (username) WHERE gaming_clients.username=varUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = varUsername, LOWER(username) = BINARY LOWER(varUsername)) AND client_id!=clientID AND is_account_closed=0;  

  SELECT COUNT(*) INTO @numNickname FROM gaming_clients WHERE nickname=varNickname AND client_id!=clientID AND is_account_closed=0; 
  SELECT COUNT(*) INTO @numMob FROM gaming_clients WHERE mob=varMob AND client_id!=clientID AND is_account_closed=0; 
  SELECT COUNT(*) INTO @numSecretQuestion FROM gaming_client_secret_questions WHERE client_secret_question_id=clientSecretQuestionID; 
  SELECT COUNT(*) INTO @numClientSegment                
  FROM gaming_client_segments
  JOIN gaming_client_segment_groups ON
    gaming_client_segment_groups.is_payment_group=1 AND
    gaming_client_segments.client_segment_group_id=gaming_client_segment_groups.client_segment_group_id 
  WHERE gaming_client_segments.client_segment_id=clientSegmentID;
  
   -- Check if Secret Question ID chosen is invalid
  IF(clientSecretQuestionID IS NOT NULL AND @numSecretQuestion = 0)
    THEN SET @numSecretQuestion = -1;
   END  IF;
  
  SELECT username, @numCountries, @numLanguages, @numEmail, @numUsername, @numNickname, @numMob, @numClientSegment, @numSecretQuestion
  FROM gaming_clients WHERE client_id=clientID;

END$$

DELIMITER ;

