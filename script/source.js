// This example shows how to make a call to an open API (no authentication required)
// to retrieve the results of an nfl match

// Refer to https://github.com/smartcontractkit/functions-hardhat-starter-kit#javascript-code

// Arguments can be provided when a request is initated on-chain and used in the request source code as shown below
const game_id = args[0];
// const toSymbol = args[1];

// make HTTP request
const res_url = 'https://v1.american-football.api-sports.io/games?id=' + game_id
console.log(`HTTP GET Request to ${url}`);

// construct the HTTP Request object. See: https://github.com/smartcontractkit/functions-hardhat-starter-kit#javascript-code
// params used for URL query parameters
const gameRequest = Functions.makeHttpRequest({
  url: url,
  headers: {
    "Content-Type": "application/json",
    'x-rapidapi-key': '0d7371b74cfe8afb33bf3dbc9abaa414', 
    'x-rapidapi-host': 'v1.american-football.api-sports.io'
  }
});

// Execute the API request (Promise)
const gameResponse = await gameRequest;
if (gameResponse.error) {
  console.error(gameResponse.error);
  throw Error("Request failed");
}

const ret = {
    id: res.data.response[0].game.id,
    finished: res.data.response[0].game.status.short == "FT",
    home: res.data.response[0].scores.home.total,
    away: res.data.response[0].scores.away.total
}

// extract the price
console.log(ret);
// encode into uint

// finished 0 or 1
// home win = 0, away win = 1
// difference uint 16
// game id can be uint32
let bits = 0;
bits |= ret.finished
bits |= ret.home > ret.away ? 0 : 1 << 1
bits |= Math.abs(ret.home - ret.away) << 2
bits |= ret.id << 18
console.log(bits);
// Solidity doesn't support decimals so multiply by 100 and round to the nearest integer
// Use Functions.encodeUint256 to encode an unsigned integer to a Buffer


return Functions.encodeUint256(bits);