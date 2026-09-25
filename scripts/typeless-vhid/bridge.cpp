#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>

namespace driver = pqrs::karabiner::driverkit::virtual_hid_device_driver;
namespace service = pqrs::karabiner::driverkit::virtual_hid_device_service;
namespace {
constexpr const char* socket_path = "/var/run/sayall-vhid-bridge.sock";
std::atomic<bool> running{true};
void stop(int) { running = false; }
}

int main(int argc, char** argv) {
  if (argc != 2 || geteuid() != 0) {
    std::cerr << "usage: sudo sayall-vhid-bridge <authorized-uid>\n";
    return 2;
  }
  char* end = nullptr;
  auto allowed_uid = static_cast<uid_t>(strtoul(argv[1], &end, 10));
  if (*end != '\0' || allowed_uid == 0) return 2;
  std::signal(SIGINT, stop);
  std::signal(SIGTERM, stop);
  pqrs::dispatcher::extra::initialize_shared_dispatcher();
  auto client = std::make_unique<service::client>();
  std::atomic<bool> ready{false};
  client->connected.connect([&] {
    service::virtual_hid_keyboard_parameters parameters;
    parameters.set_country_code(pqrs::hid::country_code::us);
    client->async_virtual_hid_keyboard_initialize(parameters);
  });
  client->virtual_hid_keyboard_ready.connect([&](bool value) { ready = value; });
  client->async_start();

  int server = socket(AF_UNIX, SOCK_STREAM, 0);
  if (server < 0) return 1;
  sockaddr_un address{};
  address.sun_family = AF_UNIX;
  std::strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);
  struct stat old{};
  if (lstat(socket_path, &old) == 0) {
    if (!S_ISSOCK(old.st_mode) || (old.st_uid != 0 && old.st_uid != allowed_uid)) return 1;
    unlink(socket_path);
  }
  umask(0177);
  if (bind(server, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
      chown(socket_path, allowed_uid, -1) != 0 || chmod(socket_path, 0600) != 0 ||
      listen(server, 4) != 0) {
    perror("bridge socket");
    return 1;
  }
  std::cout << "bridge listening" << std::endl;
  while (running) {
    int peer = accept(server, nullptr, nullptr);
    if (peer < 0) continue;
    uid_t peer_uid = 0;
    gid_t peer_gid = 0;
    char key = 0;
    const bool authorized = getpeereid(peer, &peer_uid, &peer_gid) == 0 && peer_uid == allowed_uid;
    const bool valid = authorized && read(peer, &key, 1) == 1 && (key == 'v' || key == 't' || key == 'q');
    if (valid && ready) {
      auto send = [&](bool control, bool option, bool pressed) {
        driver::hid_report::keyboard_input report;
        if (control) report.modifiers.insert(driver::hid_report::modifier::left_control);
        if (option) report.modifiers.insert(driver::hid_report::modifier::left_option);
        if (pressed) {
          auto usage = key == 'v' ? pqrs::hid::usage::keyboard_or_keypad::keyboard_v :
                       key == 't' ? pqrs::hid::usage::keyboard_or_keypad::keyboard_t :
                                    pqrs::hid::usage::keyboard_or_keypad::keyboard_q;
          report.keys.insert(type_safe::get(usage));
        }
        client->async_post_report(report);
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
      };
      send(true, false, false);
      send(true, true, false);
      send(true, true, true);
      send(true, true, false);
      send(true, false, false);
      send(false, false, false);
      std::cout << "posted " << key << std::endl;
      key = '1';
    } else {
      key = '0';
    }
    (void)write(peer, &key, 1);
    close(peer);
  }
  client->async_stop();
  close(server);
  unlink(socket_path);
}
