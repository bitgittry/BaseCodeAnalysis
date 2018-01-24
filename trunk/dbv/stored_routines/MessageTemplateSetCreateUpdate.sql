DROP procedure IF EXISTS `MessageTemplateSetCreateUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageTemplateSetCreateUpdate`(
  messageTemplateSetID BIGINT(20), displayName VARCHAR(80), DescriptionVar VARCHAR(500), createdByUserID BIGINT(20), 
  changedByUserID BIGINT(20), OUT statusCode INT, OUT lastInsertID BIGINT(20))
root: BEGIN

	DECLARE titleAlreadyExists TINYINT(1) DEFAULT 0;
	
	SET statusCode = 0;

	SELECT 1 INTO titleAlreadyExists
	FROM gaming_message_template_set
	WHERE display_name = displayName
	AND is_hidden = 0;

	IF (messageTemplateSetID IS NULL AND titleAlreadyExists) THEN
	SET statusCode = 1;
	LEAVE root;
	END IF;

	IF messageTemplateSetID IS NULL THEN
	INSERT INTO gaming_message_template_set (display_name,description,created_by_user_id,created_on,changed_by_user_id,changed_on)
	VALUES  (displayName, DescriptionVar, createdByUserID, NOW(), null, null);
	SET lastInsertID = LAST_INSERT_ID();
	ELSE

	-- if updating a template set to a title that already exists
	IF (titleAlreadyExists AND displayName NOT IN (SELECT display_name FROM gaming_message_template_set WHERE message_template_set_id = messageTemplateSetID)) THEN
	SET statusCode = 1;
	LEAVE root;
	END IF;

	UPDATE  gaming_message_template_set SET display_name = displayName,
			description = DescriptionVar, changed_by_user_id = changedByUserID,changed_on = NOW()
	
	WHERE gaming_message_template_set.message_template_set_id = messageTemplateSetID;
	SET lastInsertID = messageTemplateSetID;
	END IF;

END$$

DELIMITER ;

