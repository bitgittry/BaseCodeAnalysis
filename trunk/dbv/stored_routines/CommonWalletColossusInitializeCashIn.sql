DROP procedure IF EXISTS `CommonWalletColossusInitializeCashIn`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusInitializeCashIn`(gameManufacturerId BIGINT, percentageToBuy DECIMAL(5,2), pbOfferId BIGINT, amountToBuyPC DECIMAL(18,5), OUT statusCode INT)
root:BEGIN

-- Status Codes : 1 = amount doesn't match expected.

DECLARE amountInBase, fullOfferAmount, percentageAlreadyBought, clientStatId, exchangeRateToColossusCur, amountInPoolCurrency DECIMAL(18,5);
DECLARE poolID, cwTransactionID, pbBetID BIGINT(20);
DECLARE extOfferID, merchantRefForTicket VARCHAR(60);
SET statusCode = 0;

SELECT pb_bet_id INTO pbBetID
FROM gaming_pb_offers
WHERE gaming_pb_offers.pb_offer_id = pbOfferId
LIMIT 1;

SELECT SUM(IFNULL(accepted_percent,0)) AS AcceptedPercent INTO percentageAlreadyBought
FROM gaming_pb_offers
LEFT JOIN gaming_pb_accepted_offers ON gaming_pb_accepted_offers.pb_offer_id = gaming_pb_offers.pb_offer_id
WHERE pb_bet_id = pbBetID
GROUP BY pb_bet_id
LIMIT 1;


-- Determine if amount stated to buy is correct
SELECT gaming_pb_offers.pb_pool_id, gaming_pb_offers.client_stat_id, offer_amount, ext_offer_id, gaming_pb_bets.cw_transaction_id INTO poolID, clientStatId, fullOfferAmount, extOfferID, merchantRefForTicket
FROM gaming_pb_offers
LEFT JOIN gaming_pb_accepted_offers ON gaming_pb_offers.pb_offer_id = gaming_pb_accepted_offers.pb_offer_id
JOIN gaming_pb_bets ON gaming_pb_offers.pb_bet_id = gaming_pb_bets.pb_bet_id
WHERE gaming_pb_offers.pb_offer_id = pbOfferId AND gaming_pb_offers.game_manufacturer_id = gameManufacturerId
LIMIT 1;

-- Get currency exchange rate for pool
SELECT exchange_rate INTO exchangeRateToColossusCur
FROM gaming_client_stats
JOIN gaming_pb_pool_exchange_rates exchange_rates ON gaming_client_stats.currency_id = exchange_rates.currency_id AND exchange_rates.pb_pool_id = poolID
WHERE gaming_client_stats.client_stat_id = clientStatId;


-- SET amountInPoolCurrency = (fullOfferAmount * ((100 - IFNULL(percentageAlreadyBought,0))/100)) * (percentageToBuy/100);
SET amountInPoolCurrency = (fullOfferAmount * (percentageToBuy/100));
-- IF((amountToBuyPC * exchangeRateToColossusCur) != amountInBase) THEN
-- SET statusCode = 1;
-- LEAVE root;
-- END IF;

-- Merchant Reference, extOfferId, amountToPay, acceptanceId
INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, cw_request_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
SELECT gameManufacturerId, transaction_type.payment_transaction_type_id, request_type.cw_request_type_id, amountInPoolCurrency, UUID(), NULL, poolID, clientStatID, NULL, NOW(), NULL, 0, 0
FROM gaming_game_manufacturers
JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID AND transaction_type.name='CashIn'
LEFT JOIN gaming_cw_request_types AS request_type ON request_type.name='CashIn' AND request_type.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;
SET cwTransactionID=LAST_INSERT_ID();

SELECT merchantRefForTicket AS merchantReference, extOfferID AS externalOfferId, amountInPoolCurrency AS amountToPayColossusCur, cwTransactionID AS acceptanceId;

END root$$

DELIMITER ;

