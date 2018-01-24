
DROP function IF EXISTS `ComponentsRibbonUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `ComponentsRibbonUpdate`(
	ribbonComponentName VARCHAR(80),
	ribbonComponentDesc VARCHAR(255),
	newRibbonComponentIcon VARCHAR(45),
	newRibbonComponentIconAlt VARCHAR(45),
	newRibbonComponentTitle VARCHAR(45),
	newRibbonComponentLinkHref VARCHAR(200),
	newRibbonComponentName VARCHAR(80), -- Used for UPDATE
	newRibbonComponentDesc VARCHAR(255), -- Used for UPDATE
	linkedGamingSetting VARCHAR(80)
) RETURNS varchar(100) CHARSET utf8
BEGIN
	DECLARE tempRibbonComponentID SMALLINT;
	
	-- get component_id of page to be updated
	SELECT component_id
		FROM components_main
		WHERE name = ribbonComponentName AND description = ribbonComponentDesc AND component_type_id = 1
		INTO tempRibbonComponentID;
	
	-- UPDATE component name and description
	UPDATE components_main
		SET name=newRibbonComponentName, description=newRibbonComponentDesc
		WHERE component_id = tempRibbonComponentID;
		
	-- Update group, pages and drop down descriptions automatically
	BEGIN
		REPEAT
			UPDATE components_main c
			JOIN  components_main parent on c.parent_component_id = parent.component_id
			SET c.description = CONCAT(REPLACE(REPLACE(REPLACE((parent.description), ' Tab -', ','), ' Tab', ''),' - ', ', '), ' - ', c.name)
			WHERE c.component_type_id = 1 AND c.parent_component_id > 1;
		UNTIL ROW_COUNT() = 0 END REPEAT;
	END;
		
	-- check if parameter with icon file name is null, if not null update record in components_ribbon
	IF(newRibbonComponentLinkHref IS NOT NULL) THEN
		-- UPDATE components_ribbon data
		UPDATE components_ribbon SET icon_src = newRibbonComponentIcon, icon_alt = newRibbonComponentIconAlt, title = newRibbonComponentTitle, link_href = newRibbonComponentLinkHref, linked_gaming_setting = linkedGamingSetting
			WHERE component_id = tempRibbonComponentID;
	END IF;
		
	RETURN 'RIBBON COMPONENT UPDATED';
END$$

DELIMITER ;