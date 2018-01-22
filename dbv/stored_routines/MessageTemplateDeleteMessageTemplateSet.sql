DROP procedure IF EXISTS `MessageTemplateDeleteMessageTemplateSet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageTemplateDeleteMessageTemplateSet`(messageTemplateSetID BIGINT(20), OUT statusCode INT)
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
		UPDATE gaming_message_template_set
		SET is_hidden = 1
		WHERE message_template_set_id = messageTemplateSetID;

		UPDATE gaming_message_templates
		SET is_hidden = 1
		WHERE message_template_set_id = messageTemplateSetID;
	END IF;
END$$

DELIMITER ;