-- -------------------------------------
-- LottoHeroCancelBetAndUpdateParticipation.sql
-- -------------------------------------
DROP procedure IF EXISTS `LottoHeroCancelBetAndUpdateParticipation`;

DELIMITER $$
CREATE DEFINER = 'bit8_admin'@'127.0.0.1'
PROCEDURE LottoHeroCancelBetAndUpdateParticipation(gameSessionID BIGINT, clientStatID BIGINT, 
  gameManufacturerName VARCHAR(80), cancelTransactionRef VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  refundAmount DECIMAL(18, 5), canCommit TINYINT(1), participationId BIGINT, participationStatusCode INT, OUT statusCode INT)
root: BEGIN
  CALL CommonWalletGeneralRefundBet(gameSessionID, clientStatID, gameManufacturerName, cancelTransactionRef, transactionRef, roundRef, gameRef, refundAmount, canCommit, false, true, statusCode);

   UPDATE gaming_lottery_participations AS participation FORCE INDEX(lottery_dbg_ticket_id)
   JOIN gaming_lottery_participation_statuses AS pstatus ON pstatus.game_manufacturer_id = participation.game_manufacturer_id
   SET participation.lottery_participation_status_id = pstatus.lottery_participation_status_id
   WHERE participation.lottery_participation_id = participationId AND pstatus.status_code = participationStatusCode;

END root$$

DELIMITER ;