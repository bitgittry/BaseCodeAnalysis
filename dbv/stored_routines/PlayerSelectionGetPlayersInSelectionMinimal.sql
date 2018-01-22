DROP procedure IF EXISTS `PlayerSelectionGetPlayersInSelectionMinimal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionGetPlayersInSelectionMinimal`(playerSelectionID BIGINT, pageNumber INT, amountPerPage INT)
BEGIN
  -- Optimized
  DECLARE startNum, endNum INT DEFAULT 0;

  SET @counterID=0;
  SET startNum=(pageNumber-1)*amountPerPage;
  SET endNum=pageNumber*amountPerPage;
  
  SELECT @counterID:=@counterID+1 AS counter_id, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, gaming_clients.ext_client_id
  FROM gaming_player_selections_player_cache AS CS 
  STRAIGHT_JOIN gaming_client_stats ON CS.client_stat_id=gaming_client_stats.client_stat_id 
  STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id
  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1)
  ORDER BY CS.client_stat_id DESC
  LIMIT startNum, endNum;
  
  SELECT @counterID AS counter_id;
  
END$$

DELIMITER ;

