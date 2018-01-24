DROP procedure IF EXISTS `PlatformTypesGetPlatformsByPlatformType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlatformTypesGetPlatformsByPlatformType`(varPlatformType VARCHAR(40), varPlatformTypeID INT, OUT platformTypeID INT, OUT platformType VARCHAR(40), OUT channelTypeID INT, OUT channelType VARCHAR(40))
BEGIN
	
    -- Optimized
    
		SET platformType = NULL; 
		SET channelType =  NULL;
		SET platformTypeID = 0;
		SET channelTypeID = 0;

	-- Platform Type Code Takes Priority
  -- Platforms Are Dependant on Channels. Thanks Why we take only the is_active field of gaming_channel_types. 
  -- gaming_platform_types is_active field is only used for ui stuff
		IF (varPlatformType IS NOT NULL OR varPlatformTypeID IS NOT NULL) THEN
			SELECT gaming_platform_types.platform_type_id, gaming_platform_types.platform_type, gaming_channel_types.channel_type_id, gaming_channel_types.channel_type
			INTO platformTypeID, platformType, channelTypeID, channelType
			FROM gaming_platform_types
			STRAIGHT_JOIN gaming_channels_platform_types ON gaming_platform_types.platform_type_id = gaming_channels_platform_types.platform_type_id
			STRAIGHT_JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id
				AND gaming_channel_types.is_active = 1
			WHERE 
            (((gaming_platform_types.platform_type = varPlatformType AND varPlatformTypeID IS NULL) OR 
			  (gaming_platform_types.platform_type_id = varPlatformTypeID AND varPlatformType IS NULL))
			 OR gaming_platform_types.platform_type = varPlatformType
			) LIMIT 1;
		END IF;

	-- If platform Type is null get default Platform
	IF (platformType IS NULL) THEN
		
        SELECT gaming_platform_types.platform_type_id, gaming_platform_types.platform_type, gaming_channel_types.channel_type_id, gaming_channel_types.channel_type
		INTO platformTypeID, platformType, channelTypeID, channelType
		FROM gaming_platform_types
		STRAIGHT_JOIN gaming_channels_platform_types ON gaming_platform_types.platform_type_id = gaming_channels_platform_types.platform_type_id
		STRAIGHT_JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id 
			AND gaming_channel_types.is_active = 1
		WHERE gaming_platform_types.is_default = 1  
        LIMIT 1
        ;
	END IF;
END$$

DELIMITER ;

