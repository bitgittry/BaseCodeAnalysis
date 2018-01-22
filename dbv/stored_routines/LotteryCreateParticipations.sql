DROP procedure IF EXISTS `LotteryCreateParticipations`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryCreateParticipations`(lotteryCouponID BIGINT)
BEGIN
  -- On duplicate key we update the participations
  -- Added CONCAT(gaming_lottery_dbg_tickets.game_state_idf,'')  to use proper index


  INSERT INTO gaming_lottery_participations
	(lottery_draw_id, lottery_dbg_ticket_id, sort_order, 
	 game_state_idf, draw_number, game_manufacturer_id,
	 draw_date, lottery_participation_status_id, participation_cost, lottery_wager_status_id)
  SELECT gaming_lottery_draws.lottery_draw_id, gaming_lottery_dbg_tickets.lottery_dbg_ticket_id, 
    gaming_lottery_draws.draw_number + 1 -(IFNULL(firstDrawNumber.draw_number,activeDraw.draw_number) + IFNULL(advance_draws,0)) as sort_order,
    gaming_lottery_dbg_tickets.game_state_idf, gaming_lottery_draws.draw_number, gaming_lottery_coupons.game_manufacturer_id, 
    gaming_lottery_draws.draw_date, participation_status.lottery_participation_status_id,
    gaming_lottery_dbg_tickets.ticket_cost/IFNULL(multi_draws,1), 2
  FROM gaming_lottery_coupons FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_lottery_participation_statuses AS participation_status FORCE INDEX (manufacturer_status_code) ON 
  participation_status.status_code = '1' AND participation_status.game_manufacturer_id = gaming_lottery_coupons.game_manufacturer_id
  STRAIGHT_JOIN gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id) ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
  STRAIGHT_JOIN gaming_lottery_draws AS activeDraw FORCE INDEX (game_draw_status) ON activeDraw.game_id = gaming_lottery_dbg_tickets.game_id AND activeDraw.status = 2 
  LEFT JOIN gaming_lottery_draws AS firstDrawNumber ON firstDrawNumber.game_id = gaming_lottery_dbg_tickets.game_id AND firstDrawNumber.draw_number = gaming_lottery_dbg_tickets.first_draw_number
  STRAIGHT_JOIN gaming_lottery_draws FORCE INDEX (game_draw_number) ON  
	gaming_lottery_draws.game_id=IFNULL(firstDrawNumber.game_id, activeDraw.game_id) AND 
	gaming_lottery_draws.draw_number BETWEEN IFNULL(firstDrawNumber.draw_number,activeDraw.draw_number) + IFNULL(gaming_lottery_dbg_tickets.advance_draws,0) AND IFNULL(firstDrawNumber.draw_number,activeDraw.draw_number) + IFNULL(gaming_lottery_dbg_tickets.advance_draws,0) + IFNULL(gaming_lottery_dbg_tickets.multi_draws-1,0)
  WHERE gaming_lottery_coupons.lottery_coupon_id = lotteryCouponID
  ON DUPLICATE KEY UPDATE 
	gaming_lottery_participations.game_state_idf=VALUES(game_state_idf), 
	gaming_lottery_participations.draw_number=VALUES(draw_number), 
	gaming_lottery_participations.participation_idf=VALUES(participation_idf), 
	gaming_lottery_participations.draw_offset=VALUES(draw_offset), 
	gaming_lottery_participations.draw_date=VALUES(draw_date), 
	gaming_lottery_participations.lottery_participation_status_id=VALUES(lottery_participation_status_id);

  UPDATE gaming_lottery_dbg_tickets FORCE INDEX (PRIMARY)
  JOIN (
	SELECT gaming_lottery_dbg_tickets.lottery_dbg_ticket_id, MIN(gaming_lottery_participations.draw_number) AS first_draw_number, MAX(gaming_lottery_participations.draw_number) AS last_draw_number
    FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
	JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id=gaming_lottery_participations.lottery_dbg_ticket_id
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = lotteryCouponID
    GROUP BY gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
  ) AS Participations ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id=Participations.lottery_dbg_ticket_id
  SET gaming_lottery_dbg_tickets.first_draw_number=Participations.first_draw_number,
	  gaming_lottery_dbg_tickets.last_draw_number=Participations.last_draw_number;
END$$

DELIMITER ;

