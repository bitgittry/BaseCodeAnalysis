DROP procedure IF EXISTS `PlayerGetQuickViewVisibleFields`;

DELIMITER $$
CREATE PROCEDURE `PlayerGetQuickViewVisibleFields` ( clientStatId BIGINT(20), userId BIGINT(20))
root:BEGIN

	DECLARE userGroupId BIGINT(20);
	
	SELECT user_group_id INTO userGroupId FROM users_main WHERE user_id = userId;
    
	SELECT * FROM player_quick_view_config AS parent  
	WHERE parent.player_quick_view_config_id = (SELECT child.player_quick_view_config_id 
												FROM player_quick_view_config AS child 
												WHERE child.field_name = parent.field_name AND
													CASE 
														WHEN child.priority = 1 THEN child.entity_id = userGroupId
														WHEN child.priority = 2 THEN child.entity_id = userId
														ELSE TRUE 
													END
												ORDER BY child.priority DESC LIMIT 1)
		 AND parent.is_visible = 1
	ORDER BY parent.x_span_order;
END$$

DELIMITER ;