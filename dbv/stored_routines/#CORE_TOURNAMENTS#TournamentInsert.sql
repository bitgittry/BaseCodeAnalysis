DROP procedure IF EXISTS `TournamentInsert`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentInsert`(varName VARCHAR(80),DisplayName VARCHAR(255), TournamentTypeId TINYINT(4), TournamentDateStart DATETIME, TournamentDateEnd DATETIME,
 LeaderboardDateStart DATETIME, LeaderboardDateEnd DATETIME, PlayerSelectionID BIGINT,QualifyMinRounds INT, TournamentScoreTypeID INT,ScoreNumRounds INT,
 StakeProfitPercentage DECIMAL(18,5),CurrencyID BIGINT,BonusRuleID BIGINT, PrizeType VARCHAR(20), AutomaticAwardPrize TINYINT(1), WagerReqRealOnly TINYINT(1), 
 CurrencyProfileID BIGINT, GameWeightProfileID BIGINT, SBWeightProfileID BIGINT, OUT statusCode INT, OUT tournamentID BIGINT)
root: BEGIN
 
  DECLARE checkValue BIGINT DEFAULT 0; 
  DECLARE checkValueTinyInt TINYINT DEFAULT 0;

  SET statusCode = 0;

  SELECT tournament_id INTO checkValue FROM gaming_tournaments WHERE name = varName AND is_hidden=0;
  IF (checkValue IS NOT NULL AND checkValue != 0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SET checkValue = NULL;

  SELECT player_selection_id INTO checkValue FROM gaming_player_selections WHERE player_selection_id=PlayerSelectionID AND IFNULL(is_hidden, 0) = 0;
  IF (checkValue IS NULL OR checkValue=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

    SET checkValue = NULL;

  SELECT tournament_type_id INTO checkValueTinyInt FROM gaming_tournament_types WHERE tournament_type_id=TournamentTypeId;
  IF (checkValueTinyInt IS NULL OR checkValueTinyInt=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;

  SET checkValue = NULL;

  SELECT tournament_score_type_id INTO checkValue FROM gaming_tournament_score_types WHERE tournament_score_type_id=TournamentScoreTypeID;
  IF (checkValue IS NULL OR checkValue=0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;

  SET checkValue = NULL;

  SELECT currency_id INTO checkValue FROM gaming_currency WHERE currency_id = CurrencyID;
  IF (checkValue IS NULL OR checkValue=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;

  SET checkValue = NULL;

  IF (PrizeType='BONUS') THEN
    SELECT bonus_rule_id INTO checkValue FROM gaming_bonus_rules WHERE bonus_rule_id = bonusRuleID;
    IF (checkValue IS NULL OR checkValue=0) THEN
      SET statusCode=6;
      LEAVE root;
    END IF;
  END IF;

  INSERT INTO gaming_tournaments (name,display_name,tournament_type_id,tournament_date_start,tournament_date_end,leaderboard_date_start,leaderboard_date_end
    ,player_selection_id,qualify_min_rounds,tournament_score_type_id,score_num_rounds,stake_profit_percentage,currency_id,bonus_rule_id,prize_type,automatic_award_prize, wager_req_real_only
    ,currency_profile_id,game_weight_profile_id,sb_weight_profile_id
  ) VALUES (varName,DisplayName,TournamentTypeId,TournamentDateStart,TournamentDateEnd,LeaderboardDateStart,LeaderboardDateEnd,PlayerSelectionID,QualifyMinRounds,
     TournamentScoreTypeID,ScoreNumRounds,StakeProfitPercentage,CurrencyID,bonusRuleID,PrizeType,AutomaticAwardPrize, WagerReqRealOnly,
     CurrencyProfileID,GameWeightProfileID,SBWeightProfileID);

  SET tournamentID = LAST_INSERT_ID();

END$$

DELIMITER ;

