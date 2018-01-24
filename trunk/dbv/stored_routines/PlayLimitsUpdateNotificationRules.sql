DROP procedure IF EXISTS `PlayLimitsUpdateNotificationRules`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitsUpdateNotificationRules`(play_limit_type_name VARCHAR(20), play_interval_type_name VARCHAR(20), license_type_name VARCHAR(20), channel_type VARCHAR(20), notify_for_game_limit tinyint(1), notify_at_percentage decimal(18,5), is_active tinyint(1), user_id bigint(20), play_limit_notification_rule_id bigint(20))
BEGIN

	SET @play_interval_type_name = play_interval_type_name;
	SET @play_limit_type_name = play_limit_type_name;	
	SET @license_type_name = license_type_name;
	SET @channel_type = IFNULL(channel_type, 'all');
	SET @notify_for_game_limit = notify_for_game_limit;
	SET @notify_at_percentage = notify_at_percentage;
	SET @is_active = is_active;
	SET @user_id = user_id;
	SET @play_limit_notification_rule_id = play_limit_notification_rule_id;


	IF ((SELECT COUNT(*) 
			FROM gaming_play_limits_notification_rules notification_rules 
			JOIN gaming_play_limit_type as limit_types 			
			JOIN gaming_license_type as license_types ON license_types.name = @license_type_name
			JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type
			LEFT JOIN gaming_interval_type as interval_types ON interval_types.name = @play_interval_type_name
			WHERE 
				notification_rules.play_limit_type_id = limit_types.play_limit_type_id
				AND notification_rules.license_type_id = license_types.license_type_id
				AND notification_rules.channel_type_id = gaming_channel_types.channel_type_id
				AND  IF(@play_interval_type_name IS NULL,notification_rules.interval_type_id IS NULL, notification_rules.interval_type_id = interval_types.interval_type_id)
				AND notification_rules.notify_for_game_limit = @notify_for_game_limit
				AND notification_rules.notify_at_percentage = @notify_at_percentage
				AND notification_rules.is_active = @is_active
				AND limit_types.name = @play_limit_type_name
				AND (notification_rules.play_limit_notification_rule_id != @play_limit_notification_rule_id OR @play_limit_notification_rule_id IS NULL)) > 0)                
		THEN 
			SELECT 1;
		ELSE 
			IF (@is_active) 
				THEN 
					UPDATE gaming_play_limits_notification_rules as notification_rules
					JOIN gaming_play_limit_type as limit_types ON limit_types.name = @play_limit_type_name
					JOIN gaming_license_type as license_types ON license_types.name = @license_type_name
					JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type
					LEFT JOIN gaming_interval_type as interval_types ON interval_types.name = @play_interval_type_name					
					SET notification_rules.play_limit_type_id = limit_types.play_limit_type_id, 
						notification_rules.license_type_id = license_types.license_type_id,
						notification_rules.channel_type_id = gaming_channel_types.channel_type_id,
						notification_rules.interval_type_id = interval_types.interval_type_id,
						notification_rules.notify_at_percentage = @notify_at_percentage,
						notification_rules.notify_for_game_limit = @notify_for_game_limit,
						notification_rules.user_id = @user_id,
						notification_rules.last_modified_date = NOW()
					WHERE notification_rules.play_limit_notification_rule_id = @play_limit_notification_rule_id;
			ELSE
				UPDATE gaming_play_limits_notification_rules SET is_active = false, last_modified_date = NOW() WHERE play_limit_notification_rule_id = @play_limit_notification_rule_id;
			END IF;
			
			SELECT 0;
	END IF;
END$$

DELIMITER ;