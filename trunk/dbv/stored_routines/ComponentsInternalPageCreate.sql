
DROP function IF EXISTS `ComponentsInternalPageCreate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `ComponentsInternalPageCreate`(
	internalPageName VARCHAR(80),
	internalPageDesc VARCHAR(255),
	internalPageLink VARCHAR(200),
	internalPageOrder INT(11),
	internalShowInPage TINYINT(4),
	parentName VARCHAR(255),
	parentDesc VARCHAR(255),
	linkedGamingSetting VARCHAR(80)
) RETURNS varchar(100) CHARSET utf8
BEGIN
	DECLARE tempParentID SMALLINT;
	DECLARE tempInternalPageID SMALLINT;
	DECLARE tempSuperUserID BIGINT(20);
	DECLARE tempRightsResult SMALLINT;
	DECLARE tempNewOrder INT(11);
	DECLARE tempExistingOrderCnt INT(11);
	DECLARE tempRowCount SMALLINT;
	
	-- get component_id of parent component, save it in tempParentID
	SELECT component_id
		FROM components_main
		WHERE name = parentName AND description = parentDesc AND component_type_id = 1
		INTO tempParentID;
	
	-- if order is not specified, get new order for new component
	IF(internalPageOrder IS NULL) THEN
		SELECT IF(MAX(`order`) IS NULL, 0, MAX(`order`) + 1)
			FROM components_main
			WHERE parent_component_id = tempParentID
			INTO tempNewOrder;
	ELSE
		SET tempNewOrder = internalPageOrder;
	END IF;
	
	-- check if existing component has same order
	SELECT COUNT(component_id)
		FROM components_main
		WHERE parent_component_id = tempParentID AND `order` = tempNewOrder
		INTO tempExistingOrderCnt;
	
	-- UPDATE internal pages order
	IF(tempExistingOrderCnt > 0) THEN
		UPDATE components_main SET `order` = `order` + 1
			WHERE parent_component_id = tempParentID AND `order` >= tempNewOrder;
	END IF;
	
	-- INSERT
	INSERT INTO components_main (server_id, name, description, parent_component_id, component_type_id, active, `order`)
		VALUES (1, internalPageName, internalPageDesc, tempParentID, 4, 1, tempNewOrder)
		ON DUPLICATE KEY UPDATE server_id=1; /* redundant update in case of duplicate record */
	
	SELECT ROW_COUNT() INTO tempRowCount;
	
	-- if no row is inserted, user tried to add new controller with same details
	IF(tempRowCount > 0) THEN
		-- get new component_id
		SELECT LAST_INSERT_ID() INTO tempInternalPageID;
		
		-- obtain super admin ID
		SELECT user_type_id
			FROM users_type
			WHERE default_level = 0 LIMIT 1
			INTO tempSuperUserID;
		
		-- add rights of new system internal page to super admin user
		SELECT AssignRightsForGroup(tempSuperUserID, tempInternalPageID, 1, 0, 0, 0, 0) INTO tempRightsResult;
		
		-- page rights of new system internal page (by default always view permission)
		INSERT INTO components_pages_types (component_id, is_view)
			VALUES (tempInternalPageID, 1);
		
		-- add page URL to components ribbon
		INSERT INTO components_ribbon (component_id, link_href, show_in_device_manage, linked_gaming_setting)
			VALUES (tempInternalPageID, internalPageLink, internalShowInPage, linkedGamingSetting);
		
		RETURN tempInternalPageID; -- success, return new component id
	END IF;
	
	RETURN -1; -- error when user tries to add new controller with same details
END$$

DELIMITER ;