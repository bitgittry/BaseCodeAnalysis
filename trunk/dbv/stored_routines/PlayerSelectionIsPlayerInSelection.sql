DROP function IF EXISTS `PlayerSelectionIsPlayerInSelection`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayerSelectionIsPlayerInSelection`(playerSelectionID BIGINT, clientStatID BIGINT) RETURNS tinyint(1)
    READS SQL DATA
BEGIN
  -- Backward compatibility 
  RETURN PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter(playerSelectionID, clientStatID, 0, 1);
END$$

DELIMITER ;

