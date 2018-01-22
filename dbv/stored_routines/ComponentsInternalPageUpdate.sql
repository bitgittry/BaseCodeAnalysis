
DROP function IF EXISTS `ComponentsInternalPageUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `ComponentsInternalPageUpdate`(
	internalPageName VARCHAR(80),
	internalPageDesc VARCHAR(255),
	newInternalPageName VARCHAR(80), -- Used for UPDATE
	newInternalPageDesc VARCHAR(255), -- Used for UPDATE
	newInternalPageLink VARCHAR(200), -- Used for UPDATE
	newInternalPageOrder INT(11),
	newInternalShowInPage TINYINT(4),
	linkedGamingSetting VARCHAR(80)
) RETURNS varchar(100) CHARSET utf8
BEGIN
	DECLARE tempParentID SMALLINT;
	DECLARE tempInternalPageID SMALLINT;
	DECLARE tempNewOrder INT(11);
	DECLARE tempExistingOrderCnt INT(11);
	DECLARE tempOldOrder INT(11);
	DECLARE tempOrderChange INT(11);
	
	-- get component_id of system internal page to be updated
	SELECT component_id
		FROM components_main
		WHERE name=internalPageName AND description=internalPageDesc AND component_type_id = 4
		INTO tempInternalPageID;
	
	-- get component_id of parent component, save it in tempParentID
	SELECT parent_component_id
		FROM components_main
		WHERE component_id = tempInternalPageID
		INTO tempParentID;
		
	-- if order is not specified, get new order for new component
	IF(newInternalPageOrder IS NULL) THEN
		SELECT IF(MAX(`order`) IS NULL, 0, MAX(`order`) + 1)
			FROM components_main
			WHERE parent_component_id = tempParentID
			INTO tempNewOrder;
	ELSE
		SET tempNewOrder = newInternalPageOrder;
	END IF;
	
	-- check if existing component has same order
	SELECT COUNT(component_id)
		FROM components_main
		WHERE parent_component_id = tempParentID AND `order` = tempNewOrder
		INTO tempExistingOrderCnt;
	
	SELECT `order`
		FROM components_main
		WHERE component_id = tempInternalPageID
		INTO tempOldOrder;
	
	-- UPDATE internal pages order
	IF(tempExistingOrderCnt > 0) THEN
		IF(tempNewOrder > tempOldOrder) THEN
			UPDATE components_main SET `order` = `order` - 1
				WHERE parent_component_id = tempParentID AND `order` BETWEEN tempOldOrder AND tempNewOrder;
		ELSE
			UPDATE components_main SET `order` = `order` + 1
				WHERE parent_component_id = tempParentID AND `order` BETWEEN tempNewOrder AND tempOldOrder;
		END IF;
	END IF;
	
	-- UPDATE internal page name and description
	UPDATE components_main SET name = newInternalPageName, description = newInternalPageDesc, `order` = tempNewOrder
		WHERE component_id = tempInternalPageID;
	
	-- UPDATE internal page url in components ribbon
	UPDATE components_ribbon SET link_href = newInternalPageLink, show_in_device_manage = newInternalShowInPage, linked_gaming_setting = linkedGamingSetting
		WHERE component_id = tempInternalPageID;
	
	RETURN 'INTERNAL PAGE UPDATED';
	
END$$

DELIMITER ;