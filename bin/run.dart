import "dart:async";

import "package:dslink/client.dart";
import "package:dslink/responder.dart";

import "package:irc/client.dart";

SimpleNode rootNode;
LinkProvider link;
Map<String, DSAClient> clients;

main(List<String> args) async {
  link = new LinkProvider(args, "IRC-", command: "run", defaultNodes: {
  }, profiles: {});

  link.connect();

  rootNode = link.provider.getNode("/");

  var config = new Configuration(host: "irc.esper.net", port: 6667, nickname: "DSAIRC", username: "DSAIRC");
  var bot = new DSAClient("EsperNET", config);

  bot.onReady.listen((event) {
    event.join("#directcode");
  });

  bot.onBotJoin.listen((event) {
    var client = event.client as DSAClient;
    String channel = event.channel.name.substring(1);
    link.addNode("/${client.serverName}/Channels/$channel", {});
    // TODO: Fix this... Does irc.dart not have users yet? NOTE: Nothing is returned.
    // event.channel.allUsers.forEach((user) => link.addNode("/${client.serverName}/Channels/$channel/$user", {}));
  });

  bot.onBotPart.listen((event) {
    var client = event.client as DSAClient;
    link.removeNode("/${client.serverName}/Channels/${event.channel.name.substring(1)}");
  });

  bot.onKick.listen((event) {
    var client = event.client as DSAClient;
    if (event.user == event.client.nickname) {
      link.removeNode("/${client.serverName}/Channels/${event.channel.name.substring(1)}");
    }
  });

  bot.connect();
}

class DSAClient extends Client {

  String serverName;

  DSAClient(String serverName, Configuration config) : super(config) {
    link.addNode("/$serverName", {});
    link.addNode("/$serverName/Channels", {});
    this.serverName = serverName;
  }

  Stream<KickEvent> get onKick => onEvent(KickEvent);

}

