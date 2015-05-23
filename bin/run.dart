import "dart:async";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

import "package:irc/client.dart";

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "IRC-", command: "run", defaultNodes: {
    "Create_Bot": {
      r"$name": "Create Bot",
      r"$is": "createBot",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "host",
          "type": "string"
        },
        {
          "name": "port",
          "type": "number",
          "default": 6667
        },
        {
          "name": "nickname",
          "type": "string",
          "default": "DSABot"
        },
        {
          "name": "username",
          "type": "string",
          "default": "DSABot"
        },
        {
          "name": "channels",
          "type": "array",
          "default": []
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ]
    }
  }, profiles: {
    "createBot": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      var name = params["name"];
      var host = params["host"];
      var port = params["port"];
      var nickname = params["nickname"];
      var username = params["username"];
      var channels = params["channels"];

      if (name == null || host == null || port == null || nickname == null || username == null || channels == null) {
        return {
          "success": false,
          "message": "Failed: A required parameter was not specified."
        };
      }

      link.addNode("/${name}", {
        r"$is": "client",
        r"$irc_host": host,
        r"$irc_port": port,
        r"$irc_nickname": nickname,
        r"$irc_username": username,
        r"$irc_channels": channels.join(","),
        "Connect": {
          r"$is": "connect",
          r"$invokable": "write"
        },
        "Disconnect": {
          r"$is": "disconnect",
          r"$invokable": "write",
          r"$params": [
            {
              "name": "reason",
              "type": "string",
              "default": "Bot Disconnecting"
            }
          ]
        }
      });

      link.save();

      return {
        "success": true,
        "message": "Success!"
      };
    }),
    "client": (String path) => new ClientNode(path),
    "leaveChannel": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      ClientNode node = getClientNode(path);
      node.client.part(getChannelNodeName(path));
      return {};
    }),
    "disconnect": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      ClientNode node = getClientNode(path);
      if (node.client.connected) {
        node.client.disconnect(reason: params["reason"]);
      }
      return {};
    }),
    "connect": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      ClientNode node = getClientNode(path);
      if (!node.client.connected) {
        node.client.connect();
      }
      return {};
    }),
    "sendChannelMessage": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      ClientNode node = getClientNode(path);
      node.client.sendMessage(getChannelNodeName(path), params["message"] == null ? "" : params["message"]);
      return {};
    })
  }, encodePrettyJson: true, autoInitialize: false);

  link.init();
  link.connect();
}

ClientNode getClientNode(String path) => link[path.split("/").take(2).join("/")];
String getChannelNodeName(String path) => "#${path.split("/")[3]}";

class ClientNode extends SimpleNode {
  DSAClient client;

  Path myPath;

  String get server => myPath.name;

  ClientNode(String path) : super(path) {
    myPath = new Path(path);
  }

  @override
  void onCreated() {
    init();

    if (!children.containsKey("Connect")) {
      put("/Connect", {
        r"$is": "connect",
        r"$invokable": "write"
      });
    }

    if (!children.containsKey("Disconnect")) {
      put("/Disconnect", {
        r"$is": "disconnect",
        r"$invokable": "write",
        r"$params": [
          {
            "name": "reason",
            "type": "string",
            "default": "Bot Disconnecting"
          }
        ]
      });
    }
  }

  bool _initialized = false;

  void val(String path, value) => link.updateValue("/${server}${path}", value);
  SimpleNode put(String path, Map map) => link.addNode("/${server}${path}", map);
  SimpleNode addValue(String path, String type, {dynamic value, String name}) {
    var map = {};
    map[r"$type"] = type;
    if (name != null) map[r"$name"] = name;
    if (value != null) map["?value"] = value;
    return put(path, map);
  }

  void rm(String path) => link.removeNode("/${server}${path}");
  void rmc(String path) {
    var p = link.getNode("/${server}${path}");
    p.children.keys.map((it) => "${p.path}/${it}").forEach(link.removeNode);
  }

  init() async {
    addValue("/Connected", "bool", value: false);
    addValue("/Ready", "bool", value: false);

    if (_initialized) {
      return;
    }

    _initialized = true;

    var node = link.getNode(path);

    var config = new Configuration(
        host: node.get(r"$irc_host"),
        port: node.get(r"$irc_port"),
        nickname: node.get(r"$irc_nickname"),
        username: node.get(r"$irc_username")
    );

    List<String> defaultChannels = [];
    if (node.getConfig(r"$irc_channels") != null) {
      defaultChannels = node.getConfig(r"$irc_channels").split(",");
    }

    DSAClient bot = client = new DSAClient(new Path(path).name, config);

    bot.onConnect.listen((ConnectEvent event) {
      val("/Connected", true);
    });

    bot.onReady.listen((event) {
      val("/Ready", true);

      for (var channel in defaultChannels) {
        if (!channel.startsWith("#")) {
          channel = "#${channel}";
        }
        event.join(channel);
      }
    });

    bot.onDisconnect.listen((DisconnectEvent event) {
      val("/Ready", false);
      val("/Connected", false);
      rmc("/Channels");
    });

    bot.onBotJoin.listen((event) async {
      String channel = getChannelName(event.channel.name);
      put("/Channels/${channel}", {
        "Leave": {
          r"$is": "leaveChannel",
          r"$invokable": "write",
          r"$result": "values"
        },
        "Send_Message": {
          r"$name": "Send Message",
          r"$is": "sendChannelMessage",
          r"$invokable": "write",
          r"$result": "values",
          r"$params": [
            {
              "name": "message",
              "type": "string"
            }
          ]
        }
      });
      await new Future.delayed(new Duration(seconds: 1));
      for (var user in event.channel.allUsers) {
        await addUserToChannel(client, channel, user);
      }
    });

    bot.onBotPart.listen((event) {
      String channel = getChannelName(event.channel.name);
      rm("/Channels/${channel}");
    });

    bot.onJoin.listen((event) async {
      DSAClient client = event.client;
      String channel = getChannelName(event.channel.name);
      String user = event.user;
      await addUserToChannel(client, channel, user);
    });

    bot.onPart.listen((event) {
      String channel = getChannelName(event.channel.name);
      String user = event.user;
      rm("/Channels/${channel}/${user}");
    });

    bot.onKick.listen((event) {
      if (event.user == event.client.nickname) {
        rm("/Channels/${getChannelName(event.channel.name)}");
      }
    });

    bot.connect();
  }

  @override
  Map save() {
    var map = {
      r"$is": "client"
    };

    for (var c in configs.keys) {
      if (c.startsWith(r"$irc_")) {
        map[c] = configs[c];
      }
    }

    for (var m in children.keys) {
      if (m == "Channels") continue;
      map[m] = children[m];
    }

    return map;
  }
}

addUserToChannel(DSAClient client, String channel, String user) async {
  WhoisEvent whois = await client.whois(user);
  link.addNode("/${client.serverName}/Channels/${channel}/${user}", {
    "Username": {
      r"$type": "string",
      "?value": whois.username
    },
    "Realname": {
      r"$type": "string",
      "?value": whois.realname
    }
  });
}

String getChannelName(String input) => input.substring(1);

class DSAClient extends Client {
  String serverName;

  DSAClient(String serverName, Configuration config) : super(config) {
    link.addNode("/$serverName", {});
    link.addNode("/$serverName/Channels", {});
    this.serverName = serverName;
  }

  Stream<KickEvent> get onKick => onEvent(KickEvent);
}

