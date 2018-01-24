DROP procedure IF EXISTS `MessageGreetingGetCurrent`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageGreetingGetCurrent`(clientID BIGINT(20), platformTypeID TINYINT(4), languageCode VARCHAR(5))
BEGIN

DECLARE messageGreetingID BIGINT(20);
DECLARE hasLang TINYINT(1) DEFAULT 0;
DECLARE hasPlatform TINYINT(1) DEFAULT 0;

SELECT message_greeting_id INTO messageGreetingID FROM gaming_message_greetings
WHERE gaming_message_greetings.is_hidden = 0
AND PlayerSelectionIsPlayerInSelectionCached(gaming_message_greetings.player_selection_id, clientID)
AND ((gaming_message_greetings.date_from <= NOW() AND gaming_message_greetings.date_to >= NOW())
					OR  (gaming_message_greetings.is_never_ending = 1 AND gaming_message_greetings.date_from <= NOW() AND gaming_message_greetings.date_to IS NULL)
					OR	(gaming_message_greetings.date_from IS NULL AND gaming_message_greetings.date_to IS NULL))
ORDER BY gaming_message_greetings.priority ASC LIMIT 1;

IF (messageGreetingID IS NOT NULL) THEN
	SELECT 1 INTO hasLang
	FROM gaming_message_greetings
	JOIN gaming_message_template_set ON gaming_message_greetings.message_template_set_id = gaming_message_template_set.message_template_set_id
	JOIN gaming_message_templates ON gaming_message_templates.message_template_set_id = gaming_message_template_set.message_template_set_id AND gaming_message_templates.is_active = 1 
	JOIN gaming_languages ON gaming_message_templates.language_id = gaming_languages.language_id
	WHERE gaming_message_greetings.message_greeting_id = messageGreetingID AND language_code = languageCode LIMIT 1;

	SELECT 1 INTO hasPlatform
	FROM gaming_message_greetings
	JOIN gaming_message_template_set ON gaming_message_greetings.message_template_set_id = gaming_message_template_set.message_template_set_id
	JOIN gaming_message_templates ON gaming_message_templates.message_template_set_id = gaming_message_template_set.message_template_set_id AND gaming_message_templates.is_active = 1 
	LEFT JOIN gaming_platform_types ON gaming_message_templates.platform_type_id = gaming_platform_types.platform_type_id
	WHERE gaming_message_greetings.message_greeting_id = messageGreetingID AND  gaming_message_templates.platform_type_id = platformTypeID LIMIT 1;

	 SELECT gaming_message_greetings.priority, gaming_message_templates.message_template_id,gaming_message_templates.message_template_set_id,gaming_message_templates.platform_type_id, gaming_message_templates.language_id,
						gaming_languages.language_code,gaming_message_templates.message,gaming_message_templates.is_active,gaming_message_templates.timestamp, 
						gaming_message_templates.is_default, gaming_message_template_set.display_name, gaming_message_greetings.message_greeting_id AS greeting_id, gaming_message_greetings.display_name AS greeting_title
	 
						FROM gaming_message_templates
						JOIN gaming_message_template_set ON gaming_message_templates.message_template_set_id = gaming_message_template_set.message_template_set_id
						JOIN gaming_message_greetings ON gaming_message_greetings.message_template_set_id = gaming_message_template_set.message_template_set_id
						JOIN gaming_languages ON gaming_message_templates.language_id = gaming_languages.language_id
						LEFT JOIN gaming_platform_types ON gaming_message_templates.platform_type_id = gaming_platform_types.platform_type_id
						WHERE message_greeting_id = messageGreetingID AND gaming_message_templates.is_hidden = 0 AND
						((gaming_languages.language_code = languageCode AND hasLang = 1 ) OR (gaming_languages.is_default = 1 AND hasLang = 0 ))
						AND gaming_message_templates.is_active = 1 
						AND gaming_message_greetings.notification_event_type_id = 2
						AND ((gaming_platform_types.platform_type_id = platformTypeID AND hasPlatform = 1 ) OR (gaming_message_templates.is_default = 1 AND hasPlatform = 0));

END IF;
 
END$$

DELIMITER ;

