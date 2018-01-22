DROP procedure IF EXISTS `CommonWalletColossusPlaceCashIn`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusPlaceCashIn`(clientStatID BIGINT, extPoolID BIGINT, cashInAmountPoolCurrency DECIMAL(18,5), offerID BIGINT, betMerchantRef BIGINT, acceptedID BIGINT, percentageBought DECIMAL(5,2), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN


DECLARE clientStatIDCheck, clientID, currencyID, countryID, sessionID,clientWagerTypeID, licenseTypeID,poolID,
			betGamePlayID, gameManufacturerID, gameRoundID, gamePlayID,numTransactions  BIGINT DEFAULT -1;
DECLARE exchangeRate, CashInAmount, winReal, betTotal, winRealBase, taxModificationPlayer, taxModificationPlayerBonus, taxModificationOperator, taxModificationOperatorBonus DECIMAL(18, 5) DEFAULT 0;
DECLARE licenseType VARCHAR(20) DEFAULT NULL;
DECLARE playLimitEnabled TINYINT(1) DEFAULT 0;
 
SET statusCode =0;
SET clientWagerTypeID = 6;
SET licenseType = 'poolbetting';
SET licenseTypeID = 5;

SELECT gs1.value_bool as vb1
INTO playLimitEnabled
FROM gaming_settings gs1 
WHERE gs1.name='PLAY_LIMIT_ENABLED';

-- lock gaming_client_stats
SELECT client_stat_id, gaming_clients.client_id, gaming_client_stats.currency_id,country_id,exchange_rate,sessions_main.session_id 
INTO clientStatIDCheck, clientID, currencyID, countryID,exchangeRate,sessionID
FROM gaming_client_stats 
JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
LEFT JOIN sessions_main ON extra_id = gaming_client_stats.client_stat_id AND is_latest AND sessions_main.status_code=1 
JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = gaming_client_stats.currency_id
WHERE client_stat_id=clientStatID
FOR UPDATE;


IF (clientStatIDCheck=-1) THEN 
	SET statusCode = 1;
	LEAVE root;
END IF;

-- Determine player currency cash in amount
SELECT cashInAmountPoolCurrency*exchange_rate,gaming_pb_pools.pb_pool_id INTO CashInAmount, poolID
FROM gaming_pb_pool_exchange_rates 
JOIN gaming_pb_pools ON  gaming_pb_pool_exchange_rates.pb_pool_id =gaming_pb_pools.pb_pool_id
WHERE gaming_pb_pool_exchange_rates.currency_id = currencyID AND ext_pool_id = extPoolID;

-- Retrieve game round and bet game play id
SELECT ggp.game_play_id, ggp.game_round_id, ggp.game_manufacturer_id, ggp.amount_total
INTO betGamePlayID, gameRoundID, gameManufacturerID, betTotal
FROM gaming_game_plays AS ggp
JOIN gaming_cw_transactions AS cw_tran ON cw_tran.game_play_id = ggp.game_play_id
WHERE cw_tran.cw_transaction_id=betMerchantRef AND is_win_placed=0 AND ggp.payment_transaction_type_id=12;

IF (betGamePlayID=-1) THEN
	SET statusCode=2;
	LEAVE root;
END IF;

SELECT num_transactions 
INTO numTransactions
FROM gaming_game_rounds
WHERE game_round_id=gameRoundID;


SET winReal=CashInAmount;
SET winRealBase=ROUND(winReal/exchangeRate,5);

UPDATE gaming_client_stats AS gcs
LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
SET 
	gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+ROUND((winReal - taxModificationPlayer),0), 
	gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxModificationPlayer, gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus + taxModificationPlayerBonus,

	gcsession.total_win=gcsession.total_win+winReal, gcsession.total_win_base=gcsession.total_win_base+winRealBase, gcsession.total_win_real=gcsession.total_win_real+winReal,

	gcws.num_wins=gcws.num_wins+IF(winReal>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal
WHERE gcs.client_stat_id=clientStatID;  

INSERT INTO gaming_game_plays 
(amount_total, amount_total_base, exchange_rate, amount_real, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus,extra_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, amount_bonus, amount_bonus_win_locked, balance_bonus_after, balance_bonus_win_locked_after) 
SELECT winReal, winRealBase, exchangeRate, winReal, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID, pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer, taxModificationPlayerBonus, taxModificationOperatorBonus,poolID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), 0,0, 0,0
FROM gaming_payment_transaction_type
JOIN gaming_client_stats ON gaming_payment_transaction_type.name='CashIn' AND gaming_client_stats.client_stat_id=clientStatID
LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='PoolCashIn';

SET gamePlayID=LAST_INSERT_ID();

CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID); 

INSERT INTO gaming_game_plays_pb (game_play_id,pb_fixture_id,pb_outcome_id,pb_pool_id,payment_transaction_type_id,client_id,client_stat_id,amount_total,amount_total_base,amount_total_pool_currency,
amount_real,amount_real_base,timestamp,exchange_rate,currency_id,country_id,pb_league_id, amount_bonus, amount_bonus_base)
SELECT gamePlayID,ggpp.pb_fixture_id,ggpp.pb_outcome_id,ggpp.pb_pool_id,ggp.payment_transaction_type_id,ggp.client_id,ggp.client_stat_id,ggp.amount_total,ggp.amount_total_base,cashInAmountPoolCurrency,
ggp.amount_real,ggp.amount_real/exchangeRate, NOW(), exchangeRate, currencyID, countryID, ggpp.pb_league_id, 0, 0
FROM gaming_game_plays_pb AS ggpp
JOIN gaming_game_plays AS ggp ON ggp.game_play_id = gamePlayID
WHERE ggpp.game_play_id = betGamePlayID;

IF (winReal > 0 AND playLimitEnabled) THEN
	CALL PlayLimitsUpdate(clientStatID, licenseType, winReal, 0);
END IF;

UPDATE gaming_game_rounds
JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
SET 
	win_total=win_total+winReal, win_total_base=ROUND(win_total_base+winRealBase,5), win_real=win_real+winReal,
	win_bet_diffence_base=win_total_base-bet_total_base,
	date_time_end= NOW(), is_round_finished=0, num_transactions=num_transactions+1, 
	balance_real_after=current_real_balance
WHERE game_round_id=gameRoundID;  

SET gamePlayIDReturned=gamePlayID;
SET statusCode =0;

UPDATE gaming_cw_transactions
SET 
	game_play_id = gamePlayID,
	is_success = 1
WHERE cw_transaction_id = acceptedID;

INSERT INTO gaming_pb_accepted_offers
(game_play_id, pb_offer_id, cw_transaction_id, accepted_percent)
VALUES
(gamePlayID, offerID, acceptedID, percentageBought);

END root$$

DELIMITER ;

