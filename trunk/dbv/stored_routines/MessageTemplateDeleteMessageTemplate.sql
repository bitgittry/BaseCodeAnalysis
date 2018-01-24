DROP procedure IF EXISTS `MessageTemplateDeleteMessageTemplateSetByPlatform`;
DROP procedure IF EXISTS `MessageTemplateDeleteMessageTemplate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageTemplateDeleteMessageTemplate`(messageTemplateSetID BIGINT(20), platformTypeID INT, OUT statusCode INT)
root: BEGIN
	
	DECLARE greetingsAssociated INT(11);
	SET statusCode = 0;
	
	IF NOT EXISTS(SELECT 1 FROM gaming_message_template_set WHERE message_template_set_id = messageTemplateSetID AND is_hidden = 0) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;

	SELECT COUNT(*) INTO greetingsAssociated FROM gaming_message_greetings WHERE message_template_set_id = messageTemplateSetID AND is_hidden = 0;
	
	IF (greetingsAssociated > 0) THEN
		SET statusCode = 2;
	ELSE
		UPDATE gaming_message_templates
		SET is_hidden = 1
        WHERE message_template_set_id = messageTemplateSetID AND ((platformTypeID IS NULL AND platform_type_id IS NULL) OR (platformTypeID IS NOT NULL AND platform_type_id = platformTypeID));
	END IF;
END$$

DELIMITER ;