import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/stellar_dag"
import topbar from "../vendor/topbar"

let hooksDAG = {};

hooksDAG.WorkflowCanvas = {
  mounted() {
    this.canvas = this.el;
    this.viewport = this.el.querySelector('#viewport');
    this.tempPath = this.el.querySelector('#temp-connection');
    
    this.zoom = parseFloat(this.el.dataset.zoom) || 1;
    this.pan = { x: parseFloat(this.el.dataset.panX) || 0, y: parseFloat(this.el.dataset.panY) || 0 };
    
    this.dragState = { type: null };

    this.bindEvents();
  },

  bindEvents() {
    this.canvas.addEventListener('mousedown', (e) => this.onMouseDown(e));
    window.addEventListener('mousemove', (e) => this.onMouseMove(e));
    window.addEventListener('mouseup', (e) => this.onMouseUp(e));
  },

  onMouseDown(e) {
    if (e.target.closest('.connect-source')) {
      e.stopPropagation();
      const nodeId = e.target.closest('.connect-source').dataset.id;
      const nodeEl = this.el.querySelector(`#node-${nodeId}`);
      this.dragState = { type: 'connect', sourceId: nodeId, sourceNode: nodeEl };
      this.tempPath.classList.remove('hidden');
      return;
    }

    const node = e.target.closest('.node');
    if (node) {
      e.stopPropagation();
      const rect = node.getBoundingClientRect();
      this.dragState = {
        type: 'node',
        element: node,
        id: node.dataset.id,
        offsetX: (e.clientX - rect.left) / this.zoom,
        offsetY: (e.clientY - rect.top) / this.zoom
      };
      return;
    }

    this.canvas.style.cursor = 'grabbing';
    this.dragState = { type: 'pan', startX: e.clientX - this.pan.x, startY: e.clientY - this.pan.y };
  },

  onMouseMove(e) {
    if (!this.dragState.type) return;

    if (this.dragState.type === 'node') {
      const canvasRect = this.canvas.getBoundingClientRect();
      let x = (e.clientX - canvasRect.left - this.pan.x) / this.zoom - this.dragState.offsetX;
      let y = (e.clientY - canvasRect.top - this.pan.y) / this.zoom - this.dragState.offsetY;
      
      this.dragState.element.style.left = `${Math.max(0, x)}px`;
      this.dragState.element.style.top = `${Math.max(0, y)}px`;
    } 
    else if (this.dragState.type === 'pan') {
      this.pan.x = e.clientX - this.dragState.startX;
      this.pan.y = e.clientY - this.dragState.startY;
      this.updateViewport();
    }
    else if (this.dragState.type === 'connect') {
      const canvasRect = this.canvas.getBoundingClientRect();
      const mouseX = (e.clientX - canvasRect.left - this.pan.x) / this.zoom;
      const mouseY = (e.clientY - canvasRect.top - this.pan.y) / this.zoom;
      
      const sourceX = parseFloat(this.dragState.sourceNode.style.left) + 224;
      const sourceY = parseFloat(this.dragState.sourceNode.style.top) + 60;

      const cp1X = sourceX + Math.abs(mouseX - sourceX) * 0.4;
      const cp2X = mouseX - Math.abs(mouseX - sourceX) * 0.4;

      this.tempPath.setAttribute('d', `M ${sourceX} ${sourceY} C ${cp1X} ${sourceY}, ${cp2X} ${mouseY}, ${mouseX} ${mouseY}`);
    }
  },

  onMouseUp(e) {
    if (!this.dragState.type) return;

    if (this.dragState.type === 'node') {
      const x = parseFloat(this.dragState.element.style.left);
      const y = parseFloat(this.dragState.element.style.top);
      this.pushEvent("update_node_position", { id: this.dragState.id, x, y });
    } 
    else if (this.dragState.type === 'pan') {
      this.canvas.style.cursor = 'grab';
      this.pushEvent("update_viewport", { pan_x: this.pan.x, pan_y: this.pan.y, zoom: this.zoom });
    }
    else if (this.dragState.type === 'connect') {
      this.tempPath.classList.add('hidden');
      const target = document.elementFromPoint(e.clientX, e.clientY)?.closest('.node');
      
      if (target && target.dataset.id !== this.dragState.sourceId) {
        this.pushEvent("add_connection", { from: this.dragState.sourceId, to: target.dataset.id });
      }
    }

    this.dragState = { type: null };
  },

  updateViewport() {
    this.viewport.style.transform = `translate(${this.pan.x}px, ${this.pan.y}px) scale(${this.zoom})`;
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...hooksDAG},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

