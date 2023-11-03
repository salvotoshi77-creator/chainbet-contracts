const API_KEY = "097516329686c249a3940fbcb3732a86"
const url = "https://api.the-odds-api.com/v4/sports?apiKey=" + API_KEY
const main = async () => {
    console.log('Hello World!');
    await gameResult();
}
const axios = require('axios');
// function to get result
const gameResult = async () => {
    // const res_url = 'https://v1.american-football.api-sports.io/games?id=7798'
    const res_url = 'https://v1.american-football.api-sports.io/games?id=7649'

    const res = await axios.get(res_url, { headers: { 'x-rapidapi-key': '0d7371b74cfe8afb33bf3dbc9abaa414', 'x-rapidapi-host': 'v1.american-football.api-sports.io' } })
    /*
    {
        id,
        finished: bool,
        home: int, // score
        away: int
    }
    */
    const ret = {
        id: res.data.response[0].game.id,
        finished: res.data.response[0].game.status.short == "FT",
        home: res.data.response[0].scores.home.total,
        away: res.data.response[0].scores.away.total
    }
    // const ret = {
    //     id: 0,
    //     finished: true,
    //     home: 14,
    //     away: 3
    // }

    console.log(ret)
    let bits = 0;
    bits |= ret.finished
    bits |= ret.home > ret.away ? 0 : 1 << 1
    bits |= Math.abs(ret.home - ret.away) << 2
    bits |= ret.id << 18
    console.log(bits);
}


// function to get odds

main().then();