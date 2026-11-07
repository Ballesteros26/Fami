// Modal dialogs: one shows at a time, the rest wait in a queue.
#pragma once

#include <functional>
#include <string>

#include "app.h"

namespace gss {

struct App::Modal {
	std::string title;
	std::function<bool()> body;  // draws the contents; returns false to close
	bool opened = false;
};

}  // namespace gss
