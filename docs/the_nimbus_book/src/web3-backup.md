# Add a backup web3 provider

It's a good idea to add a backup web3 provider in case your main one goes down. You can do this by simply repeating the `--web3-url` parameter on launch.

> Warning: As of `v1.7.0` Nimbus will no longer automagically rewrite HTTP(S) web3 URLs to their respective WebSocket alternatives.

For example, if your primary EL client is a [local Geth](./eth1.md#geth), but you want to use [Infura](./infura-guide.md) as a backup you would run:

```
./run-mainnet-beacon-node.sh \
 --web3-url="ws://127.0.0.1:8546" \
 --web3-url="wss://mainnet.infura.io/ws/v3/..."
```

