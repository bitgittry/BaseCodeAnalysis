DROP procedure IF EXISTS `TournamentInsertPrize`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentInsertPrize`(tournamentID BIGINT, prizePosition INT, wagerRequirement DECIMAL(18,5), OUT tournamentPrizeID BIGINT)
BEGIN
  -- checking if exists
  SELECT tournament_prize_id INTO tournamentPrizeID FROM gaming_tournament_prizes WHERE tournament_id=tournamentID AND prize_position=prizePosition;

  IF (tournamentPrizeID IS NULL OR tournamentPrizeID=0) THEN 
	  INSERT INTO gaming_tournament_prizes (tournament_id, prize_position, wager_requirement_multiplier) 
	  VALUES (tournamentID, prizePosition, wagerRequirement);
	  
	  SET tournamentPrizeID = LAST_INSERT_ID();
  ELSE
	 UPDATE gaming_tournament_prizes SET wager_requirement_multiplier=wagerRequirement WHERE tournament_prize_id=tournamentPrizeID;	
  END IF;
	
END$$

DELIMITER ;

