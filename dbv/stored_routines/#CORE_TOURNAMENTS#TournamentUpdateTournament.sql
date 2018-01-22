DROP procedure IF EXISTS `TournamentUpdateTournament`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentUpdateTournament`(tournamentID BIGINT,varName VARCHAR(80),DisplayName VARCHAR(255), TournamentTypeId TINYINT(4), TournamentDateStart DATETIME, TournamentDateEnd DATETIME,
 LeaderboardDateStart DATETIME, LeaderboardDateEnd DATETIME, PlayerSelectionID BIGINT,QualifyMinRounds INT, TournamentScoreTypeID INT,ScoreNumRounds INT,
 StakeProfitPercentage DECIMAL(18,5),CurrencyID BIGINT,BonusRuleID BIGINT, PrizeType VARCHAR(20), AutomaticAwardPrize TINYINT(1), WagerReqRealOnly TINYINT(1), 
 CurrencyProfileID BIGINT, GameWeightProfileID BIGINT, SBWeightProfileID BIGINT, OUT statusCode INT)
root: BEGIN

  DECLARE checkValue BIGINT DEFAULT 0; 

  SET statusCode = 0;

  SELECT  tournament_id INTO checkValue FROM gaming_tournaments WHERE name = varName AND is_hidden=0 AND tournament_id!=tournamentID;
  IF (checkValue!=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT player_selection_id INTO checkValue FROM gaming_player_selections WHERE player_selection_id=PlayerSelectionID;
  IF (checkValue=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  SET statusCode = 0;

  SELECT tournament_type_id INTO checkValue FROM gaming_tournament_types WHERE tournament_type_id=TournamentTypeId;
  IF (checkValue=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  SET statusCode = 0;

  SELECT tournament_score_type_id INTO checkValue FROM gaming_tournament_score_types WHERE tournament_score_type_id=TournamentScoreTypeID;
  IF (checkValue=0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  SET statusCode = 0;

  SELECT currency_id INTO checkValue FROM gaming_currency WHERE currency_id = CurrencyID;
  IF (checkValue=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  SET statusCode = 0;

  IF (PrizeType='BONUS') THEN
    SELECT bonus_rule_id INTO checkValue FROM gaming_bonus_rules WHERE bonus_rule_id = bonusRuleID;
    IF (checkValue=0) THEN
      SET statusCode=6;
      LEAVE root;
    END IF;
  END IF;

  UPDATE gaming_tournaments
  SET name = varName, display_name = DisplayName, tournament_type_id = TournamentTypeId, tournament_date_start = TournamentDateStart
  ,tournament_date_end = TournamentDateEnd, leaderboard_date_start = LeaderboardDateStart, leaderboard_date_end = LeaderboardDateEnd
  ,player_selection_id = PlayerSelectionID, qualify_min_rounds = QualifyMinRounds, tournament_score_type_id = TournamentScoreTypeID
  ,score_num_rounds = ScoreNumRounds, stake_profit_percentage = StakeProfitPercentage, currency_id = CurrencyID
  ,bonus_rule_id = bonusRuleID, prize_type = PrizeType, automatic_award_prize = AutomaticAwardPrize, wager_req_real_only = WagerReqRealOnly
  ,currency_profile_id = CurrencyProfileID
  ,game_weight_profile_id = GameWeightProfileID
  ,sb_weight_profile_id = SBWeightProfileID
  WHERE tournament_id=tournamentID;

END$$

DELIMITER ;

