// pw-dump monitor messages contain partial object updates. Keep the device
// routes and node properties needed to match each source to its physical ports.
function updateObjects(objects, updates) {
  for (const update of updates) {
    if (update.info === null) {
      delete objects[update.id];
      continue;
    }
    if (!update.info)
      continue;
    const previous = objects[update.id];
    const type = update.type || (previous && previous.type);
    if (type !== "PipeWire:Interface:Device" && type !== "PipeWire:Interface:Node")
      continue;
    const object = previous || { type: type, props: {}, routes: [] };
    if (update.info.props)
      object.props = Object.assign({}, object.props, update.info.props);
    if (update.info.params && Array.isArray(update.info.params.EnumRoute))
      object.routes = update.info.params.EnumRoute;
    objects[update.id] = object;
  }
}

function unavailableSources(objects) {
  const unavailable = {};
  for (const object of Object.values(objects)) {
    if (object.type !== "PipeWire:Interface:Node"
        || object.props["media.class"] !== "Audio/Source")
      continue;
    const device = objects[object.props["device.id"]];
    const profileDevice = object.props["card.profile.device"];
    if (!device || profileDevice === undefined)
      continue;
    const routes = device.routes.filter(route => route.direction === "Input"
      && (route.devices || []).some(id => String(id) === String(profileDevice)));
    // Unknown availability is normal for built-in microphones. Only hide a
    // source when every matching physical route is explicitly unavailable.
    if (routes.length > 0 && routes.every(route => route.available === "no"))
      unavailable[object.props["node.name"]] = true;
  }
  return unavailable;
}
