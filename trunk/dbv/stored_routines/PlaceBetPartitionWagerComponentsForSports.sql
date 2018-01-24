DROP procedure IF EXISTS `PlaceBetPartitionWagerComponentsForSports`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetPartitionWagerComponentsForSports`(
  clientStatID BIGINT, sbBetID BIGINT, betAmount DECIMAL(18,5), bonusEnabledFlag TINYINT(1), disableBonusMoney TINYINT(1), 
  useFreeBet TINYINT(1), allowBadDept TINYINT(1), INOUT numBonusInstances INT, INOUT betReal DECIMAL (18,5), 
  INOUT betBonus DECIMAL (18,5), INOUT betBonusWinLocked DECIMAL (18,5), INOUT betFreeBet DECIMAL (18,5), 
  INOUT betFreeBetWinLocked DECIMAL (18,5), INOUT badDeptReal DECIMAL (18,5), INOUT statusCode INT)
root: BEGIN

  -- Bad Dept with real full amount

  DECLARE totalPlayerBalance, balanceReal, balanceBonus, balanceWinLocked, balanceFreeBet, balaneFreeBetWinLocked DECIMAL (18,5) DEFAULT 0;
  DECLARE betRemain DECIMAL (18, 5) DEFAULT 0;	
  DECLARE disallowNegativeBalance TINYINT(1) DEFAULT 0;

	-- Get the settings   
	SELECT gs1.value_bool
	INTO disallowNegativeBalance
	FROM gaming_settings gs1 
	WHERE gs1.name='WAGER_DISALLOW_NEGATIVE_BALANCE';

  SELECT current_real_balance, current_bonus_balance, current_bonus_win_locked_balance
  INTO balanceReal, balanceBonus, balanceWinLocked   
  FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1;

  -- Get the bonus balance that can be used to wager bonus on this particular betslip  
  IF (disableBonusMoney OR bonusEnabledFlag=0) THEN

    SET balanceBonus=0;
    SET balanceWinLocked=0; 
    SET balanceFreeBet=0; 
    SET balaneFreeBetWinLocked=0;

  ELSE

	  -- Get the bonus balance that can be used to wager bonus on this particular betslip
	  SELECT COUNT(*), IFNULL(SUM(IF(gbta.name='Bonus', gbi.bonus_amount_remaining, 0)),0) AS current_bonus_balance, IFNULL(SUM(IF(gbta.name='Bonus', gbi.current_win_locked_amount, 0)),0) AS current_bonus_win_locked_balance,
		IFNULL(SUM(IF(gbta.name='FreeBet', gbi.bonus_amount_remaining, 0)),0) AS freebet_balance, IFNULL(SUM(IF(gbta.name='FreeBet', gbi.current_win_locked_amount, 0)),0) AS freebet_win_locked_balance
	  INTO numBonusInstances, balanceBonus, balanceWinLocked, balanceFreeBet, balaneFreeBetWinLocked
	  FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
	  STRAIGHT_JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gbi.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
	  STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id=gbr.bonus_rule_id
	  STRAIGHT_JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id=gbta.bonus_type_awarding_id
	  STRAIGHT_JOIN gaming_bonus_types ON gbr.bonus_type_id=gaming_bonus_types.bonus_type_id
	  WHERE gbi.client_stat_id=clientStatID AND gbi.is_active=1;
	  
	  SET balanceWinLocked=balanceWinLocked+balaneFreeBetWinLocked; 
	  SET balaneFreeBetWinLocked=0;

  END IF;
  
  IF (useFreeBet) THEN
    SET balanceReal=0;
    SET balanceBonus=0;
    SET balanceWinLocked=0;
    SET balaneFreeBetWinLocked=0;
  ELSE
    SET balanceFreeBet=0;
  END IF;
  
  SET totalPlayerBalance = IF(disableBonusMoney=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balaneFreeBetWinLocked));
  
  IF (allowBadDept=0 AND totalPlayerBalance < betAmount) THEN 
    SET statusCode=4;
  END IF;

  -- Partition the bet between free bet, real, bonus and bonus win locked
  SET betRemain=betAmount;
    
  IF (disableBonusMoney=0) THEN
    IF (betRemain > 0) THEN
      IF (balanceFreeBet >= betRemain) THEN
        SET betFreeBet=ROUND(betRemain, 5);
        SET betRemain=0;
      ELSE
        SET betFreeBet=ROUND(balanceFreeBet, 5);
        SET betRemain=ROUND(betRemain-betFreeBet,0);
      END IF;
    END IF;
  END IF; 
  
  IF (betRemain > 0) THEN
    IF (balanceReal >= betRemain) THEN
      SET betReal=ROUND(betRemain, 5);
      SET betRemain=0;
    ELSE
      SET betReal=ROUND(balanceReal, 5);
      SET betRemain=ROUND(betRemain-betReal,0);
    END IF;
  END IF;

  IF (disableBonusMoney=0) THEN
    IF (betRemain > 0) THEN
      IF (balanceWinLocked >= betRemain) THEN
        SET betBonusWinLocked=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonusWinLocked=ROUND(balanceWinLocked,5);
        SET betRemain=ROUND(betRemain-betBonusWinLocked,0);
      END IF;
      
    END IF;
    
    IF (betRemain > 0) THEN
      IF (balanceBonus >= betRemain) THEN
        SET betBonus=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonus=ROUND(balanceBonus,5);
        SET betRemain=ROUND(betRemain-betBonus,0);
      END IF;
      
    END IF;
  END IF;
  
  -- Parition the bonus and bonus_win_locked wagered between the player's active bonuses 
  SET betBonus=betBonus+betFreeBet;
  SET betBonusWinLocked=betBonusWinLocked+betFreeBetWinLocked;

  IF (allowBadDept) THEN

	SET betReal=betReal+betRemain;
	SET badDeptReal=betRemain;
	
  ELSE

	  IF (betRemain > 0) THEN
		SET statusCode=4;
		LEAVE root;
	  END IF;

  END IF;


END root$$

DELIMITER ;

