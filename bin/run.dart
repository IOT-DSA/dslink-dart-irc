import "dart:async";

import "package:dslink/client.dart";
import "package:dslink/responder.dart";

import "package:irc/client.dart";

SimpleNode rootNode;
LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "IRC-", command: "run", defaultNodes: {
  }, profiles: {});

  var config = new Configuration(host: "irc.esper.net", port: 6667, nickname: "DSIRC", username: "DSIRC");
  var bot = new Client(config);

  bot.onReady.listen((event) {
    event.join("#directcode");
  });

  bot.onBotJoin.listen((event) {
    event.channel.sendMessage("Hello DSA World!");
  });

  bot.connect();

  link.init();
  link.connect();

  rootNode = link.provider.getNode("/");
}

