DROP procedure IF EXISTS `GameUpdateRingFencedBalances`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameUpdateRingFencedBalances`(clientStatID BIGINT, gamePlayID BIGINT)
root:BEGIN
	
  -- Fixed casing
    
  INSERT INTO gaming_game_play_ring_fenced 
	  		  (game_play_id, ring_fenced_sb_after, ring_fenced_casino_after, ring_fenced_poker_after, ring_fenced_pb_after)
  SELECT 	  gamePlayID, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
  FROM		  gaming_client_stats
  WHERE		  client_stat_id = clientStatID
  ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),   
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
	
END root$$

DELIMITER ;

