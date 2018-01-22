
DROP function IF EXISTS `ComponentsRibbonCreate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `ComponentsRibbonCreate`(
	ribbonComponentName VARCHAR(80),
	ribbonComponentDesc VARCHAR(255),
	ribbonComponentIcon VARCHAR(45),
	ribbonComponentIconAlt VARCHAR(45),
	ribbonComponentTitle VARCHAR(45),
	ribbonComponentLinkHref VARCHAR(200),
	parentName VARCHAR(255),
	parentDesc VARCHAR(255),
	linkedGamingSetting VARCHAR(80)
) RETURNS varchar(100) CHARSET utf8
BEGIN
	DECLARE tempParentID SMALLINT;
	DECLARE tempRibbonComponentID SMALLINT;
	DECLARE tempSuperUserID BIGINT(20);
	DECLARE tempRightsResult SMALLINT;
	DECLARE tempNewOrder INT(11);
	DECLARE tempRowCount SMALLINT;
	
	-- get component_id of parent component, save it in tempParentID
	SELECT component_id
		FROM components_main
		WHERE name = parentName AND description = parentDesc AND component_type_id = 1
		INTO tempParentID;
	
	-- get new order for new component
	SELECT IF(MAX(`order`) IS NULL, 0, MAX(`order`) + 1)
		FROM components_main
		WHERE parent_component_id = tempParentID
		INTO tempNewOrder;
	
	-- INSERT
	INSERT INTO components_main (server_id, name, description, parent_component_id, component_type_id, `order`)
		VALUES (1, ribbonComponentName, ribbonComponentDesc, tempParentID, 1, tempNewOrder)
		ON DUPLICATE KEY UPDATE server_id=1; /* redundant update in case of duplicate record */
	
	SELECT ROW_COUNT() INTO tempRowCount;
	
	-- if no row is inserted, user tried to add new ribbon component with same details
	IF(tempRowCount > 0) THEN
		-- Update group, pages and drop down descriptions automatically
		BEGIN
			REPEAT
				UPDATE components_main c
				JOIN  components_main parent on c.parent_component_id = parent.component_id
				SET c.description = CONCAT(REPLACE(REPLACE(REPLACE((parent.description), ' Tab -', ','), ' Tab', ''),' - ', ', '), ' - ', c.name)
				WHERE c.component_type_id = 1 AND c.parent_component_id > 1;
			UNTIL ROW_COUNT() = 0 END REPEAT;
		END;
		
		-- get new component_id
		SELECT LAST_INSERT_ID() INTO tempRibbonComponentID;
		
		-- check if parameter with icon file name is null, if not null add/update record in components_ribbon.
		IF(ribbonComponentLinkHref IS NOT NULL) THEN
			-- insert page ribbon data, if record already exists overwrite data
			INSERT INTO components_ribbon (component_id, icon_src, icon_alt, title, link_href, linked_gaming_setting)
				VALUES (tempRibbonComponentID, ribbonComponentIcon, ribbonComponentIconAlt, ribbonComponentTitle, ribbonComponentLinkHref, linkedGamingSetting)
				ON DUPLICATE KEY UPDATE icon_src=icon_src, icon_alt=icon_alt, title=title, link_href=link_href, linked_gaming_setting=linkedGamingSetting;
		END IF;
		
		-- obtain super admin ID
		SELECT user_type_id
			FROM users_type
			WHERE default_level = 0 LIMIT 1
			INTO tempSuperUserID;
		
		-- add rights of new system function to super admin user
		SELECT AssignRightsForGroup(tempSuperUserID, tempRibbonComponentID, 1, 0, 0, 0, 0) INTO tempRightsResult;
		
		RETURN tempRibbonComponentID; -- success, return new component id
	END IF;
	
	RETURN -1; -- error when user tries to add new ribbon component with same details
END$$

DELIMITER ;