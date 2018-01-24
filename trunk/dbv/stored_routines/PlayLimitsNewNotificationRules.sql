DROP procedure IF EXISTS `PlayLimitsNewNotificationRules`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitsNewNotificationRules`(play_limit_type_name VARCHAR(20), play_interval_type_name VARCHAR(20), license_type_name VARCHAR(20), channel_type VARCHAR(20), notify_for_game_limit tinyint(1), notify_at_percentage decimal(18,5), is_active tinyint(1), user_id bigint(20))
BEGIN

	SET @play_interval_type_name = play_interval_type_name;
	SET @play_limit_type_name = play_limit_type_name;	
	SET @license_type_name = license_type_name;
	SET @channel_type = IFNULL(channel_type, 'all');
	SET @notify_for_game_limit = notify_for_game_limit;
	SET @notify_at_percentage = notify_at_percentage;
	SET @is_active = is_active;
	SET @user_id = user_id;


	IF ((SELECT COUNT(*) 
			FROM gaming_play_limits_notification_rules notification_rules 
			JOIN gaming_play_limit_type as limit_types 
			LEFT JOIN gaming_interval_type as interval_types ON interval_types.name = @play_interval_type_name
			JOIN gaming_license_type as license_types ON license_types.name = @license_type_name
			JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type
			WHERE 
			notification_rules.play_limit_type_id = limit_types.play_limit_type_id
			AND notification_rules.license_type_id = license_types.license_type_id
			AND notification_rules.channel_type_id = gaming_channel_types.channel_type_id
			AND  IF(@play_interval_type_name IS NULL,notification_rules.interval_type_id IS NULL, notification_rules.interval_type_id = interval_types.interval_type_id)
			AND notification_rules.notify_for_game_limit = @notify_for_game_limit
			AND notification_rules.notify_at_percentage = @notify_at_percentage
			AND notification_rules.is_active = @is_active
			AND limit_types.name = @play_limit_type_name) > 0)
		THEN 
			SELECT 1;
		ELSE 
			INSERT INTO gaming_play_limits_notification_rules (play_limit_type_id, license_type_id, channel_type_id, interval_type_id, is_active, 
			notify_at_percentage, notify_for_game_limit, user_id, last_modified_date)
			SELECT limit_types.play_limit_type_id, license_types.license_type_id, gaming_channel_types.channel_type_id, interval_types.interval_type_id, @is_active,
			@notify_at_percentage, @notify_for_game_limit, @user_id, NOW() 
			FROM gaming_play_limit_type as limit_types 
			JOIN gaming_license_type as license_types ON license_types.name = @license_type_name
			JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type
			LEFT JOIN gaming_interval_type as interval_types ON interval_types.name = @play_interval_type_name
			WHERE limit_types.name = @play_limit_type_name; 
			SELECT 0;
	END IF;
END$$

DELIMITER ;