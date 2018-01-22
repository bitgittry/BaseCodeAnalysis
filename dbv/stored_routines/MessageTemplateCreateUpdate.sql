DROP procedure IF EXISTS `MessageTemplateCreateUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageTemplateCreateUpdate`(messageTemplateID BIGINT(20), messageTemplateSetID BIGINT(20), languageCode VARCHAR(3), platformTypeID TINYINT(4), userID BIGINT, messageValue TEXT, isActive TINYINT(1), OUT statusCode INT, OUT lastInsertID BIGINT(20))
root: BEGIN

	DECLARE messageToLong TINYINT(1);
	DECLARE defaultAlreadyExists TINYINT(1) DEFAULT 0;
	DECLARE uniqueCombinationAlreadyExists TINYINT(1);
	DECLARE isDefault TINYINT(1);
	DECLARE languageID BIGINT(20);
	SET statusCode = 0;

	SELECT language_id INTO languageID FROM gaming_languages WHERE gaming_languages.language_code = languageCode;
	SELECT (platformTypeID IS NULL) INTO isDefault;	

	SELECT LENGTH(messageValue) > message_size INTO messageToLong FROM gaming_platform_types WHERE platform_type_id = platformTypeID;
    
	IF (messageToLong) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;

	SELECT is_default INTO defaultAlreadyExists FROM gaming_message_templates WHERE message_template_set_id = messageTemplateSetID LIMIT 1;
    
    IF (defaultAlreadyExists AND platformTypeID IS NULL AND messageTemplateID IS NULL) THEN
		SET statusCode = 2;
		LEAVE root;
	END IF;

	IF (platformTypeID IS NOT NULL AND defaultAlreadyExists = 0) THEN
			SET statusCode = 4;
			LEAVE root;
		END IF;

IF (messageTemplateID IS NULL) THEN
	SELECT COUNT(*) INTO uniqueCombinationAlreadyExists FROM gaming_message_templates where message_template_set_id = messageTemplateSetID AND language_id = languageID and platform_type_id = platformTypeID AND is_hidden = 0; 
	IF (uniqueCombinationAlreadyExists > 0) THEN 
		SET statusCode = 3;
		LEAVE root;
	ELSE
		INSERT INTO gaming_message_templates (message_template_set_id,platform_type_id,language_id,message, is_active, user_id, timestamp, is_default)
		VALUES (messageTemplateSetID, platformTypeID, languageID, messageValue, IF(platformTypeID IS NULL, 1, isActive), userID, NOW(), isDefault);
		SET lastInsertID = LAST_INSERT_ID();
	END IF;

ELSE
	 SELECT COUNT(*) INTO uniqueCombinationAlreadyExists FROM gaming_message_templates where message_template_set_id = messageTemplateSetID AND language_id = languageID and platform_type_id = platformTypeID AND message_template_id != messageTemplateID AND is_hidden = 0; 
	
	IF (uniqueCombinationAlreadyExists > 0) THEN 
		SET statusCode = 3;
		LEAVE root;
	ELSE
	UPDATE gaming_message_templates SET platform_type_id = platformTypeID, language_id = languageID, message = messageValue, is_active = IF(platformTypeID IS NULL, 1, isActive), user_id = userID, timestamp = NOW(), is_default = isDefault
		WHERE gaming_message_templates.message_template_id = messageTemplateID;
		SET lastInsertID = messageTemplateID;
	END IF;
END IF;
 
END$$

DELIMITER ;

