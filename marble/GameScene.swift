import SpriteKit
import GameplayKit
import CoreMotion
import AVFoundation

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()
    
    // Sound effects dictionary
    private var sounds: [String: AVAudioPlayer] = [:]
    
    // Sound cooldowns
    private var lastRollingSoundTime: TimeInterval = 0
    private var rollingSoundCooldown: TimeInterval = 0.1 // Minimum time between rolling sounds
    
    // Sound settings
    private var soundEnabled = true
    private var hapticEnabled = true
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    func preloadSounds() {
        // Preload all game sounds
        preloadSound(filename: "marble_roll", type: "mp3")
        preloadSound(filename: "marble_collision", type: "mp3")
        preloadSound(filename: "goal_reached", type: "mp3")
        preloadSound(filename: "level_complete", type: "mp3")
        preloadSound(filename: "game_over", type: "mp3")
        preloadSound(filename: "button_click", type: "mp3")
    }
    
    private func preloadSound(filename: String, type: String) {
        guard let path = Bundle.main.path(forResource: filename, ofType: type) else {
            print("Sound file not found: \(filename).\(type)")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            let sound = try AVAudioPlayer(contentsOf: url)
            sound.prepareToPlay()
            sounds[filename] = sound
            print("Successfully loaded sound: \(filename).\(type)")
        } catch {
            print("Could not load sound file: \(error.localizedDescription)")
        }
    }
    
    func playSound(name: String, volume: Float = 1.0) {
        guard soundEnabled else { return }
        
        // Apply cooldown to marble_roll sound to prevent lag
        if name == "marble_roll" {
            let currentTime = CACurrentMediaTime()
            if currentTime - lastRollingSoundTime < rollingSoundCooldown {
                return
            }
            lastRollingSoundTime = currentTime
        }
        
        if let sound = sounds[name] {
            // Create a new player for overlapping sounds
            if sound.isPlaying {
                do {
                    let url = sound.url!
                    let newPlayer = try AVAudioPlayer(contentsOf: url)
                    newPlayer.volume = volume
                    newPlayer.play()
                } catch {
                    print("Could not play overlapping sound: \(error.localizedDescription)")
                }
            } else {
                sound.volume = volume
                sound.play()
            }
        } else {
            print("Sound not preloaded: \(name)")
        }
    }
    
    func stopSound(name: String) {
        if let sound = sounds[name] {
            sound.stop()
        }
    }
    
    func toggleSound() {
        soundEnabled = !soundEnabled
    }
    
    func toggleHaptic() {
        hapticEnabled = !hapticEnabled
    }
    
    func isSoundEnabled() -> Bool {
        return soundEnabled
    }
    
    func isHapticEnabled() -> Bool {
        return hapticEnabled
    }
    
    func debugSoundStatus() {
        print("=== Sound Manager Status ===")
        print("Sound enabled: \(soundEnabled)")
        print("Haptic enabled: \(hapticEnabled)")
        print("Loaded sounds: \(sounds.keys.joined(separator: ", "))")
        print("===========================")
    }
}

// MARK: - Score Manager
class ScoreManager {
    static let shared = ScoreManager()
    
    private let highScoreKey = "highScore"
    private let levelReachedKey = "levelReached"
    
    private init() {}
    
    func saveScore(score: Int, level: Int) {
        let currentHighScore = getHighScore()
        let currentLevelReached = getLevelReached()
        
        // Only save if this score is higher than the current high score
        if score > currentHighScore {
            UserDefaults.standard.set(score, forKey: highScoreKey)
            print("New high score saved: \(score)")
        }
        
        // Always save the highest level reached
        if level > currentLevelReached {
            UserDefaults.standard.set(level, forKey: levelReachedKey)
            print("New highest level saved: \(level)")
        }
        
        UserDefaults.standard.synchronize()
    }
    
    func getHighScore() -> Int {
        return UserDefaults.standard.integer(forKey: highScoreKey)
    }
    
    func getLevelReached() -> Int {
        return UserDefaults.standard.integer(forKey: levelReachedKey)
    }
    
    func resetScores() {
        UserDefaults.standard.removeObject(forKey: highScoreKey)
        UserDefaults.standard.removeObject(forKey: levelReachedKey)
        UserDefaults.standard.synchronize()
        print("High scores reset")
    }
}

// MARK: - Level Definition
struct MazeLevel {
    struct Wall {
        let position: CGPoint
        let size: CGSize
        let isHorizontal: Bool
        
        init(x: CGFloat, y: CGFloat, length: CGFloat, isHorizontal: Bool) {
            self.position = CGPoint(x: x, y: y)
            self.size = isHorizontal ? 
                CGSize(width: length, height: 20) : 
                CGSize(width: 20, height: length)
            self.isHorizontal = isHorizontal
        }
    }
    
    let number: Int
    let walls: [Wall]
    let goalPositions: [CGPoint]
    let startPosition: CGPoint
    let timeLimit: Int
    let difficulty: Float // 1.0 = normal, higher = harder
    let timeBonus: Int // Time bonus for completing the level
    
    // Convenience initializer with default values for backward compatibility
    init(number: Int, walls: [Wall], goalPositions: [CGPoint], startPosition: CGPoint, timeLimit: Int, difficulty: Float = 1.0, timeBonus: Int = 0) {
        self.number = number
        self.walls = walls
        self.goalPositions = goalPositions
        self.startPosition = startPosition
        self.timeLimit = timeLimit
        self.difficulty = difficulty
        self.timeBonus = timeBonus
    }
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    // Physics categories
    struct PhysicsCategory {
        static let none      : UInt32 = 0
        static let marble    : UInt32 = 0b1
        static let wall      : UInt32 = 0b10
        static let obstacle  : UInt32 = 0b100
        static let goal      : UInt32 = 0b1000
    }
    
    // Game elements
    private var marble: SKNode?
    private var scoreLabel: SKLabelNode?
    private var timeLabel: SKLabelNode?
    private var levelLabel: SKLabelNode?
    private var obstacles: [SKNode] = []
    private var goals: [SKNode] = []
    private var mazeWalls: [SKNode] = []
    
    // Game state
    private var score: Int = 0 {
        didSet {
            scoreLabel?.text = "SCORE: \(score)"
        }
    }
    private var timeRemaining: Int = 60 {
        didSet {
            timeLabel?.text = "TIME: \(timeRemaining)"
        }
    }
    private var isGameOver: Bool = false
    private var isGamePlaying: Bool = false
    private var currentLevel: Int = 1
    
    // Motion manager
    private let motionManager = CMMotionManager()
    private var timer: Timer?
    
    // Track previous velocity for collision detection
    private var previousVelocity: CGVector = .zero
    
    // UI layout properties
    private var padding: CGFloat = 10
    private var labelWidth: CGFloat = 100
    private var headerHeight: CGFloat = 40
    
    // MARK: - Scene Lifecycle
    override func didMove(to view: SKView) {
        // Setup physics
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        
        // Preload sounds
        SoundManager.shared.preloadSounds()
        SoundManager.shared.debugSoundStatus()
        
        // Create game elements
        setupBackground()
        setupUI()
        setupMarble()
        setupBoundaries()
        setupCamera()  // Add camera setup
        
        // Ready to start
        showStartButton()
    }
    
    override func willMove(from view: SKView) {
        // Clean up
        motionManager.stopDeviceMotionUpdates()
        timer?.invalidate()
    }
    
    // MARK: - Game Setup
    private func setupBackground() {
        // Create atmospheric background
        let background = SKSpriteNode(color: .black, size: size)
        background.position = CGPoint(x: size.width/2, y: size.height/2)
        background.zPosition = -1
        
        // Add pixel art texture
        background.texture = SKTexture(image: createPixelArtBackground())
        
        addChild(background)
    }
    
    private func createPixelArtBackground() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Darker background with stronger blue tint (more like Lone Survivor)
            UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            
            // Add more pronounced pixel noise
            let pixelSize: CGFloat = 2.0
            
            for x in stride(from: 0, to: 100, by: pixelSize) {
                for y in stride(from: 0, to: 100, by: pixelSize) {
                    // Increased noise density for more texture
                    if arc4random_uniform(100) < 25 {
                        let darkness = CGFloat(arc4random_uniform(15)) / 100.0
                        UIColor(red: 0.02, green: 0.02, blue: 0.08 + darkness, alpha: 1.0).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
            
            // Stronger vignette effect
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.9).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 50, y: 50),
                startRadius: 5,
                endCenter: CGPoint(x: 50, y: 50),
                endRadius: 70,
                options: []
            )
        }
    }
    
    private func setupUI() {
        // Store these values for camera positioning
        self.padding = 10
        self.labelWidth = (size.width - (padding * 4)) / 3
        self.headerHeight = 40
        
        // UI will be created in setupCamera instead
    }
    
    private func setupMarble() {
        let marbleRadius: CGFloat = 10  // Smaller marble radius
        let marble = SKShapeNode(circleOfRadius: marbleRadius)
        marble.fillColor = .white
        marble.strokeColor = .gray
        marble.position = CGPoint(x: size.width/2, y: size.height/2)
        marble.zPosition = 10
        
        // Pixel art style for marble
        let pixelArtTexture = createPixelArtMarble(size: CGSize(width: marbleRadius*2, height: marbleRadius*2))
        marble.fillTexture = SKTexture(image: pixelArtTexture)
        
        // Physics body with improved responsiveness and MUCH less bounciness
        let body = SKPhysicsBody(circleOfRadius: marbleRadius)
        body.mass = 0.1  // Slightly heavier for less erratic movement
        body.friction = 0.2  // More friction to slow it down
        body.restitution = 0.2  // Much less bouncy (was 0.4)
        body.linearDamping = 0.3  // More damping to reduce oscillation
        body.angularDamping = 0.3  // More angular damping
        body.allowsRotation = true
        body.categoryBitMask = PhysicsCategory.marble
        body.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.obstacle
        body.contactTestBitMask = PhysicsCategory.goal
        marble.physicsBody = body
        
        addChild(marble)
        self.marble = marble
    }
    
    // Create a pixel art texture for the marble
    private func createPixelArtMarble(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Background
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            let radius = size.width / 2
            let pixelSize: CGFloat = 2.0
            
            // Draw pixel art marble
            for x in stride(from: 0, to: size.width, by: pixelSize) {
                for y in stride(from: 0, to: size.height, by: pixelSize) {
                    // Calculate distance from center
                    let dx = x + pixelSize/2 - radius
                    let dy = y + pixelSize/2 - radius
                    let distanceFromCenter = sqrt(dx*dx + dy*dy)
                    
                    if distanceFromCenter <= radius {
                        // Create a metallic look with highlights
                        let angle = atan2(dy, dx)
                        let normalizedDistance = distanceFromCenter / radius
                        
                        // Base color (silver/metallic)
                        var brightness: CGFloat = 0.7 - normalizedDistance * 0.4
                        
                        // Add highlight on top-left
                        if angle > -2.4 && angle < -0.8 {
                            brightness += 0.3 * (1.0 - normalizedDistance)
                        }
                        
                        // Add shadow on bottom-right
                        if angle > 0.8 && angle < 2.4 {
                            brightness -= 0.2
                        }
                        
                        // Clamp brightness
                        brightness = max(0.2, min(0.95, brightness))
                        
                        UIColor(white: brightness, alpha: 1.0).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
        }
    }
    
    private func setupBoundaries() {
        // Create an edge loop for boundary walls
        let borderBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        borderBody.friction = 0.2
        borderBody.restitution = 0.5
        borderBody.categoryBitMask = PhysicsCategory.wall
        borderBody.collisionBitMask = PhysicsCategory.marble
        
        // Add border to scene
        let border = SKNode()
        border.physicsBody = borderBody
        addChild(border)
        
        // Add visible borders
        let borderWidth: CGFloat = 10
        let topBorder = SKSpriteNode(color: .darkGray, size: CGSize(width: size.width, height: borderWidth))
        topBorder.position = CGPoint(x: size.width/2, y: size.height - borderWidth/2)
        
        let bottomBorder = SKSpriteNode(color: .darkGray, size: CGSize(width: size.width, height: borderWidth))
        bottomBorder.position = CGPoint(x: size.width/2, y: borderWidth/2)
        
        let leftBorder = SKSpriteNode(color: .darkGray, size: CGSize(width: borderWidth, height: size.height))
        leftBorder.position = CGPoint(x: borderWidth/2, y: size.height/2)
        
        let rightBorder = SKSpriteNode(color: .darkGray, size: CGSize(width: borderWidth, height: size.height))
        rightBorder.position = CGPoint(x: size.width - borderWidth/2, y: size.height/2)
        
        // Add borders to scene
        addChild(topBorder)
        addChild(bottomBorder)
        addChild(leftBorder)
        addChild(rightBorder)
    }
    
    // MARK: - Camera Control
    private func setupCamera() {
        // Create a camera node
        let cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width/2, y: size.height/2)
        cameraNode.setScale(1.0)
        
        // Add camera to scene
        addChild(cameraNode)
        camera = cameraNode
        
        // Create a fixed UI container that will stay at the top of the screen
        let uiContainer = SKNode()
        uiContainer.position = CGPoint(x: 0, y: size.height/2 - headerHeight/2)
        cameraNode.addChild(uiContainer)
        
        // Create UI elements directly on the camera instead of copying
        // Score label with minimal style
        let scoreLabel = SKLabelNode(fontNamed: "Courier")
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.text = "SCORE: 0"
        self.scoreLabel = scoreLabel
        
        // Score backing - simple rectangle
        let scoreBacking = SKShapeNode(rectOf: CGSize(width: labelWidth, height: 30), cornerRadius: 0)
        scoreBacking.fillColor = UIColor.black
        scoreBacking.strokeColor = UIColor.red
        scoreBacking.lineWidth = 1
        scoreBacking.position = CGPoint(x: -size.width/2 + padding + labelWidth/2, y: 0)
        scoreBacking.zPosition = 91
        uiContainer.addChild(scoreBacking)
        scoreBacking.addChild(scoreLabel)
        scoreLabel.position = CGPoint(x: 0, y: 0)
        
        // Level label with minimal style
        let levelLabel = SKLabelNode(fontNamed: "Courier")
        levelLabel.fontSize = 16
        levelLabel.fontColor = .white
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.text = "LEVEL: 1"
        self.levelLabel = levelLabel
        
        // Level backing - simple rectangle
        let levelBacking = SKShapeNode(rectOf: CGSize(width: labelWidth, height: 30), cornerRadius: 0)
        levelBacking.fillColor = UIColor.black
        levelBacking.strokeColor = UIColor.white
        levelBacking.lineWidth = 1
        levelBacking.position = CGPoint(x: 0, y: 0)
        levelBacking.zPosition = 91
        uiContainer.addChild(levelBacking)
        levelBacking.addChild(levelLabel)
        levelLabel.position = CGPoint(x: 0, y: 0)
        
        // Time label with minimal style
        let timeLabel = SKLabelNode(fontNamed: "Courier")
        timeLabel.fontSize = 16
        timeLabel.fontColor = .white
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.verticalAlignmentMode = .center
        timeLabel.text = "TIME: 60"
        self.timeLabel = timeLabel
        
        // Time backing - simple rectangle
        let timeBacking = SKShapeNode(rectOf: CGSize(width: labelWidth, height: 30), cornerRadius: 0)
        timeBacking.fillColor = UIColor.black
        timeBacking.strokeColor = UIColor.blue
        timeBacking.lineWidth = 1
        timeBacking.position = CGPoint(x: size.width/2 - padding - labelWidth/2, y: 0)
        timeBacking.zPosition = 91
        uiContainer.addChild(timeBacking)
        timeBacking.addChild(timeLabel)
        timeLabel.position = CGPoint(x: 0, y: 0)
        
        // Add a header panel to the UI container
        let headerPanel = SKShapeNode(rectOf: CGSize(width: size.width, height: headerHeight))
        headerPanel.fillColor = UIColor.black
        headerPanel.strokeColor = UIColor.white
        headerPanel.lineWidth = 1
        headerPanel.position = CGPoint(x: 0, y: 0)
        headerPanel.zPosition = 90
        uiContainer.addChild(headerPanel)
    }
    
    private func updateCameraPosition() {
        guard let marble = marble, let cameraNode = camera else { return }
        
        // Smoothly move camera to follow marble, but keep Y position fixed for UI
        let targetPosition = CGPoint(x: marble.position.x, y: marble.position.y)
        let moveAction = SKAction.move(to: targetPosition, duration: 0.2)
        moveAction.timingMode = .easeOut
        cameraNode.run(moveAction)
    }
    
    // MARK: - Game Control
    func startGame() {
        // Reset game state
        isGamePlaying = true
        isGameOver = false
        score = 0
        timeRemaining = 60
        currentLevel = 1
        
        // Play button click sound
        playButtonClickSound()
        
        // Load first level
        loadLevel(currentLevel)
        
        // Hide start button and all toggle buttons
        camera?.childNode(withName: "startButton")?.removeFromParent()
        camera?.childNode(withName: "soundToggle")?.removeFromParent()
        
        // Start motion updates for device tilt
        startMotionUpdates()
        
        // Start game timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isGamePlaying else { return }
            
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.endGame()
            }
        }
    }
    
    func endGame() {
        isGamePlaying = false
        isGameOver = true
        
        // Play game over sound
        playGameOverSound()
        
        // Stop motion and timer
        motionManager.stopDeviceMotionUpdates()
        timer?.invalidate()
        
        // Show game over message
        showGameOver()
    }
    
    private func advanceToNextLevel() {
        // Increment level
        currentLevel += 1
        
        // Get the current level definition to get the time bonus
        let currentLevelDef = getLevelDefinition(for: currentLevel - 1)
        
        // Add level completion bonus
        let levelBonus = 200
        score += levelBonus
        
        // Add time bonus if available
        let timeBonus = currentLevelDef.timeBonus
        if timeBonus > 0 {
            score += timeBonus
        }
        
        // Play level complete sound
        playLevelCompleteSound()
        
        // Show level transition
        showLevelTransition(levelBonus: levelBonus, timeBonus: timeBonus)
        
        // Load next level after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.loadLevel(self.currentLevel)
        }
    }
    
    private func showLevelTransition(levelBonus: Int, timeBonus: Int) {
        // Create level transition panel
        let panel = SKShapeNode(rectOf: CGSize(width: 280, height: 200), cornerRadius: 0)
        panel.fillColor = .black
        panel.strokeColor = .white
        panel.lineWidth = 1
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.name = "levelTransitionPanel"
        panel.zPosition = 100
        
        // Add pixel art texture
        let pixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtPanel(size: CGSize(width: 280, height: 200))))
        pixelNode.size = CGSize(width: 280, height: 200)
        panel.addChild(pixelNode)
        
        // Level complete title
        let titleLabel = SKLabelNode(fontNamed: "Courier")
        titleLabel.text = "LEVEL \(currentLevel-1) COMPLETE!"
        titleLabel.fontSize = 20
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 0, y: 60)
        panel.addChild(titleLabel)
        
        // Next level message
        let nextLevelLabel = SKLabelNode(fontNamed: "Courier")
        nextLevelLabel.text = "NEXT: LEVEL \(currentLevel)"
        nextLevelLabel.fontSize = 18
        nextLevelLabel.fontColor = .white
        nextLevelLabel.position = CGPoint(x: 0, y: 20)
        panel.addChild(nextLevelLabel)
        
        // Add level bonus score display
        let bonusLabel = SKLabelNode(fontNamed: "Courier")
        bonusLabel.text = "LEVEL BONUS: +\(levelBonus) PTS"
        bonusLabel.fontSize = 16
        bonusLabel.fontColor = .green
        bonusLabel.position = CGPoint(x: 0, y: -20)
        panel.addChild(bonusLabel)
        
        // Add time bonus if available
        if timeBonus > 0 {
            let timeBonusLabel = SKLabelNode(fontNamed: "Courier")
            timeBonusLabel.text = "TIME BONUS: +\(timeBonus) PTS"
            timeBonusLabel.fontSize = 16
            timeBonusLabel.fontColor = .yellow
            timeBonusLabel.position = CGPoint(x: 0, y: -50)
            panel.addChild(timeBonusLabel)
            
            // Add total bonus
            let totalBonusLabel = SKLabelNode(fontNamed: "Courier")
            totalBonusLabel.text = "TOTAL: +\(levelBonus + timeBonus) PTS"
            totalBonusLabel.fontSize = 16
            totalBonusLabel.fontColor = .white
            totalBonusLabel.position = CGPoint(x: 0, y: -80)
            panel.addChild(totalBonusLabel)
        }
        
        // Add to camera instead of scene
        camera?.addChild(panel)
        
        // Remove panel after delay
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.8),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))
    }
    
    private func resetMarblePosition() {
        guard let marble = marble else { return }
        
        marble.position = CGPoint(x: size.width/2, y: size.height/2)
        marble.physicsBody?.velocity = .zero
        marble.physicsBody?.angularVelocity = 0
    }
    
    private func startMotionUpdates() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1/30  // Reduced from 60Hz to 30Hz to prevent rate limiting
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion, error == nil else { return }
                
                // Reduced gravity scale for more controlled movement
                let gravityScale: CGFloat = 10.0  // Reduced from 15.0
                
                // Apply gravity based on device tilt with enhanced response
                let gravity = CGVector(
                    dx: CGFloat(motion.gravity.x) * gravityScale,
                    dy: CGFloat(motion.gravity.y) * gravityScale
                )
                
                // Apply additional force based on user rotation rate for extra responsiveness
                if let marble = self.marble, let body = marble.physicsBody {
                    // Get rotation rate data
                    let rotationRate = motion.rotationRate
                    
                    // Apply additional impulse based on rotation rate (quick tilts)
                    let rotationResponse: CGFloat = 0.1  // Reduced from 0.15 for more controlled response
                    let impulseX = CGFloat(rotationRate.x) * rotationResponse
                    let impulseY = CGFloat(rotationRate.y) * rotationResponse
                    
                    // Only apply impulse if rotation is significant and limit maximum impulse
                    if abs(impulseX) > 0.02 || abs(impulseY) > 0.02 {
                        // Limit maximum impulse to prevent extreme movements
                        let maxImpulse: CGFloat = 0.5
                        let limitedImpulseX = min(maxImpulse, max(-maxImpulse, impulseY))
                        let limitedImpulseY = min(maxImpulse, max(-maxImpulse, -impulseX))
                        
                        body.applyImpulse(CGVector(dx: limitedImpulseX, dy: limitedImpulseY))
                    }
                    
                    // Store previous velocity for collision detection
                    self.previousVelocity = body.velocity
                    
                    // Update camera position to follow marble
                    self.updateCameraPosition()
                }
                
                self.physicsWorld.gravity = gravity
            }
        }
    }
    
    // MARK: - UI Elements
    private func showStartButton() {
        // Create start button
        let buttonSize = CGSize(width: 200, height: 60)
        let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 0)
        button.fillColor = .black
        button.strokeColor = .white
        button.lineWidth = 1
        button.position = CGPoint(x: 0, y: 0) // Center relative to camera
        button.name = "startButton"
        button.zPosition = 100
        
        // Add pixel art texture
        let pixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtButton(size: buttonSize)))
        pixelNode.size = buttonSize
        button.addChild(pixelNode)
        
        // Add label
        let label = SKLabelNode(fontNamed: "Courier")
        label.text = "START GAME"
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = .zero
        button.addChild(label)
        
        // Add simple pulsing animation
        let scaleUp = SKAction.scale(to: 1.03, duration: 0.5)
        let scaleDown = SKAction.scale(to: 0.97, duration: 0.5)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        button.run(SKAction.repeatForever(pulse))
        
        // Add to camera instead of scene
        camera?.addChild(button)
        
        // Add sound toggle button only (removed haptic toggle)
        addToggleButton(
            position: CGPoint(x: 0, y: -80),
            isOn: SoundManager.shared.isSoundEnabled(),
            onText: "SOUND: ON",
            offText: "SOUND: OFF",
            name: "soundToggle"
        )
    }
    
    private func addToggleButton(position: CGPoint, isOn: Bool, onText: String, offText: String, name: String) {
        let buttonSize = CGSize(width: 200, height: 40)
        let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 0)
        button.fillColor = .black
        button.strokeColor = isOn ? .green : .red
        button.lineWidth = 1
        button.position = position
        button.name = name
        button.zPosition = 100
        
        // Add pixel art texture
        let pixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtButton(size: buttonSize)))
        pixelNode.size = buttonSize
        button.addChild(pixelNode)
        
        // Add label
        let label = SKLabelNode(fontNamed: "Courier")
        label.text = isOn ? onText : offText
        label.fontSize = 16
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = .zero
        label.name = name + "Label"
        button.addChild(label)
        
        // Add to camera instead of scene
        camera?.addChild(button)
    }
    
    private func toggleSetting(node: SKNode) {
        guard let name = node.name else { return }
        
        if name.contains("sound") {
            SoundManager.shared.toggleSound()
            let isOn = SoundManager.shared.isSoundEnabled()
            updateToggleButton(node: node, isOn: isOn, onText: "SOUND: ON", offText: "SOUND: OFF")
            
            // Play sound if enabled
            if isOn {
                playButtonClickSound()
            }
        }
        
        // Debug current status
        SoundManager.shared.debugSoundStatus()
    }
    
    private func updateToggleButton(node: SKNode, isOn: Bool, onText: String, offText: String) {
        if let shapeNode = node as? SKShapeNode {
            shapeNode.strokeColor = isOn ? .green : .red
        }
        
        if let labelNode = node.childNode(withName: node.name! + "Label") as? SKLabelNode {
            labelNode.text = isOn ? onText : offText
        }
    }
    
    private func showGameOver() {
        // Save score before showing game over screen
        ScoreManager.shared.saveScore(score: score, level: currentLevel)
        let highScore = ScoreManager.shared.getHighScore()
        let isNewHighScore = score >= highScore
        
        // Create game over panel with larger size
        let panel = SKShapeNode(rectOf: CGSize(width: 320, height: 280), cornerRadius: 0)
        panel.fillColor = .black
        panel.strokeColor = .white
        panel.lineWidth = 1
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.name = "gameOverPanel"
        panel.zPosition = 100
        panel.alpha = 0 // Start invisible for fade-in
        
        // Add pixel art texture
        let pixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtPanel(size: CGSize(width: 320, height: 280))))
        pixelNode.size = CGSize(width: 320, height: 280)
        panel.addChild(pixelNode)
        
        // Game over title with glitch effect
        let gameOverLabel = SKLabelNode(fontNamed: "Courier")
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.fontSize = 28
        gameOverLabel.fontColor = .red
        gameOverLabel.position = CGPoint(x: 0, y: 100)
        panel.addChild(gameOverLabel)
        
        // Add glitch animation to game over text
        let glitchAction = SKAction.sequence([
            SKAction.moveBy(x: 2, y: 0, duration: 0.05),
            SKAction.moveBy(x: -4, y: 0, duration: 0.05),
            SKAction.moveBy(x: 2, y: 0, duration: 0.05)
        ])
        let colorChange = SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.1),
            SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0.1)
        ])
        let glitchSequence = SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.group([glitchAction, colorChange]),
            SKAction.wait(forDuration: 0.5)
        ])
        gameOverLabel.run(SKAction.repeatForever(glitchSequence))
        
        // Level reached
        let levelLabel = SKLabelNode(fontNamed: "Courier")
        levelLabel.text = "LEVEL REACHED: \(currentLevel)"
        levelLabel.fontSize = 16
        levelLabel.fontColor = .white
        levelLabel.position = CGPoint(x: 0, y: 60)
        panel.addChild(levelLabel)
        
        // Score with highlight
        let finalScoreLabel = SKLabelNode(fontNamed: "Courier")
        finalScoreLabel.text = "FINAL SCORE: \(score)"
        finalScoreLabel.fontSize = 20
        finalScoreLabel.fontColor = .yellow
        finalScoreLabel.position = CGPoint(x: 0, y: 30)
        panel.addChild(finalScoreLabel)
        
        // High score display
        let highScoreLabel = SKLabelNode(fontNamed: "Courier")
        highScoreLabel.fontSize = 16
        highScoreLabel.position = CGPoint(x: 0, y: 0)
        
        if isNewHighScore {
            highScoreLabel.text = "NEW HIGH SCORE!"
            highScoreLabel.fontColor = .green
            
            // Add pulsing animation to high score text
            let pulseAction = SKAction.sequence([
                SKAction.scale(to: 1.2, duration: 0.5),
                SKAction.scale(to: 1.0, duration: 0.5)
            ])
            highScoreLabel.run(SKAction.repeatForever(pulseAction))
        } else {
            highScoreLabel.text = "HIGH SCORE: \(highScore)"
            highScoreLabel.fontColor = .cyan
        }
        panel.addChild(highScoreLabel)
        
        // Add score counter animation
        let scoreCounterAction = SKAction.run {
            let counterLabel = SKLabelNode(fontNamed: "Courier")
            counterLabel.fontSize = 20
            counterLabel.fontColor = .yellow
            counterLabel.position = CGPoint(x: 0, y: 30)
            counterLabel.verticalAlignmentMode = .center
            counterLabel.horizontalAlignmentMode = .center
            counterLabel.name = "scoreCounter"
            panel.addChild(counterLabel)
            
            var currentCount = 0
            let countAction = SKAction.run {
                if currentCount < self.score {
                    currentCount += max(1, self.score / 50) // Faster counting for higher scores
                    counterLabel.text = "FINAL SCORE: \(currentCount)"
                } else {
                    counterLabel.text = "FINAL SCORE: \(self.score)"
                    counterLabel.removeFromParent()
                    finalScoreLabel.isHidden = false
                }
            }
            
            let sequence = SKAction.sequence([
                countAction,
                SKAction.wait(forDuration: 0.02)
            ])
            
            finalScoreLabel.isHidden = true
            counterLabel.run(SKAction.repeat(sequence, count: 50))
        }
        
        // Play again button with improved design
        let playAgainButton = SKShapeNode(rectOf: CGSize(width: 200, height: 50), cornerRadius: 0)
        playAgainButton.fillColor = .black
        playAgainButton.strokeColor = .green
        playAgainButton.lineWidth = 2
        playAgainButton.position = CGPoint(x: 0, y: -40)
        playAgainButton.name = "playAgainButton"
        
        // Add pixel art texture to button
        let buttonPixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtButton(size: CGSize(width: 200, height: 50))))
        buttonPixelNode.size = CGSize(width: 200, height: 50)
        playAgainButton.addChild(buttonPixelNode)
        
        let playAgainLabel = SKLabelNode(fontNamed: "Courier")
        playAgainLabel.text = "PLAY AGAIN"
        playAgainLabel.fontSize = 20
        playAgainLabel.fontColor = .green
        playAgainLabel.verticalAlignmentMode = .center
        playAgainLabel.horizontalAlignmentMode = .center
        playAgainLabel.position = .zero
        playAgainButton.addChild(playAgainLabel)
        
        // Add enhanced pulsing animation to button
        let scaleUp = SKAction.scale(to: 1.05, duration: 0.5)
        let scaleDown = SKAction.scale(to: 0.95, duration: 0.5)
        let colorBrighter = SKAction.customAction(withDuration: 0.5) { node, _ in
            if let shapeNode = node as? SKShapeNode {
                shapeNode.strokeColor = .green.withAlphaComponent(1.0)
            }
        }
        let colorDarker = SKAction.customAction(withDuration: 0.5) { node, _ in
            if let shapeNode = node as? SKShapeNode {
                shapeNode.strokeColor = .green.withAlphaComponent(0.7)
            }
        }
        let pulse = SKAction.sequence([
            SKAction.group([scaleUp, colorBrighter]),
            SKAction.group([scaleDown, colorDarker])
        ])
        playAgainButton.run(SKAction.repeatForever(pulse))
        
        // Add quit button
        let quitButton = SKShapeNode(rectOf: CGSize(width: 200, height: 50), cornerRadius: 0)
        quitButton.fillColor = .black
        quitButton.strokeColor = .red
        quitButton.lineWidth = 2
        quitButton.position = CGPoint(x: 0, y: -100)
        quitButton.name = "quitButton"
        
        // Add pixel art texture to quit button
        let quitButtonPixelNode = SKSpriteNode(texture: SKTexture(image: createPixelArtButton(size: CGSize(width: 200, height: 50))))
        quitButtonPixelNode.size = CGSize(width: 200, height: 50)
        quitButton.addChild(quitButtonPixelNode)
        
        let quitLabel = SKLabelNode(fontNamed: "Courier")
        quitLabel.text = "QUIT"
        quitLabel.fontSize = 20
        quitLabel.fontColor = .red
        quitLabel.verticalAlignmentMode = .center
        quitLabel.horizontalAlignmentMode = .center
        quitLabel.position = .zero
        quitButton.addChild(quitLabel)
        
        // Add subtle animation to quit button
        let quitPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        quitButton.run(SKAction.repeatForever(quitPulse))
        
        // Add buttons to panel
        panel.addChild(playAgainButton)
        panel.addChild(quitButton)
        
        // Add panel to camera instead of scene
        camera?.addChild(panel)
        
        // Animate panel appearance
        let fadeIn = SKAction.fadeIn(withDuration: 0.5)
        panel.run(SKAction.sequence([
            fadeIn,
            scoreCounterAction
        ]))
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        // Get location in both scene and camera coordinates
        let locationInScene = touch.location(in: self)
        let locationInCamera = touch.location(in: camera!)
        
        // Check for UI elements on the camera first
        if let camera = camera {
            let touchedNodesInCamera = camera.nodes(at: locationInCamera)
            
            for node in touchedNodesInCamera {
                if node.name == "startButton" || (node.parent?.name == "startButton") {
                    playButtonClickSound()
                    startGame()
                    return
                } else if node.name == "playAgainButton" || (node.parent?.name == "playAgainButton") {
                    playButtonClickSound()
                    // Remove game over panel with animation
                    if let panel = camera.childNode(withName: "gameOverPanel") {
                        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
                        panel.run(SKAction.sequence([
                            fadeOut,
                            SKAction.removeFromParent()
                        ]))
                    }
                    // Start a new game after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.startGame()
                    }
                    return
                } else if node.name == "quitButton" || (node.parent?.name == "quitButton") {
                    playButtonClickSound()
                    // Remove game over panel
                    camera.childNode(withName: "gameOverPanel")?.removeFromParent()
                    // Show start screen
                    showStartButton()
                    return
                } else if node.name?.contains("Toggle") == true || node.parent?.name?.contains("Toggle") == true {
                    let targetNode = node.name?.contains("Toggle") == true ? node : node.parent
                    playButtonClickSound()
                    toggleSetting(node: targetNode!)
                    return
                }
            }
        }
        
        // If no UI elements were touched, check for scene elements
        let touchedNodesInScene = nodes(at: locationInScene)
        
        for node in touchedNodesInScene {
            // Handle any scene-specific touch events here if needed
        }
    }
    
    // MARK: - Physics Contact
    func didBegin(_ contact: SKPhysicsContact) {
        // Determine which bodies contacted
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        // Check for marble + goal contact
        if contactMask == PhysicsCategory.marble | PhysicsCategory.goal {
            let goalNode = (contact.bodyA.categoryBitMask == PhysicsCategory.goal) ?
                contact.bodyA.node : contact.bodyB.node
            
            handleGoalContact(goalNode)
        }
    }
    
    private func handleGoalContact(_ goalNode: SKNode?) {
        guard let goalNode = goalNode, !goalNode.isHidden, isGamePlaying else { return }
        
        // Add score
        score += 100
        
        // Hide the goal
        goalNode.isHidden = true
        goalNode.physicsBody?.categoryBitMask = PhysicsCategory.none
        
        // Create a more impressive particle effect
        let emitter = SKEmitterNode()
        
        // Configure particle properties
        emitter.particleBirthRate = 300
        emitter.numParticlesToEmit = 100
        emitter.particleLifetime = 1.5
        emitter.particleLifetimeRange = 0.5
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 50
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = CGFloat.pi * 2
        
        // Particle appearance
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.8
        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = -0.1
        
        // Create a blend of colors
        emitter.particleColor = .green
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorBlendFactorRange = 0.5
        emitter.particleColorBlendFactorSpeed = -0.2
        emitter.particleColorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor.green,
            UIColor.cyan,
            UIColor.white,
            UIColor.green
        ], times: [0.0, 0.3, 0.7, 1.0])
        
        // Position at goal
        emitter.position = goalNode.position
        emitter.zPosition = 20
        addChild(emitter)
        
        // Create a flash effect
        let flash = SKSpriteNode(color: .green, size: CGSize(width: 100, height: 100))
        flash.position = goalNode.position
        flash.zPosition = 15
        flash.alpha = 0.0
        flash.blendMode = .add
        addChild(flash)
        
        // Animate the flash
        let flashSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.1),
            SKAction.fadeAlpha(to: 0.0, duration: 0.3)
        ])
        flash.run(SKAction.sequence([
            flashSequence,
            SKAction.removeFromParent()
        ]))
        
        // Create a score popup - add to camera instead of world
        let scorePopup = SKLabelNode(fontNamed: "Courier")
        scorePopup.text = "+100"
        scorePopup.fontSize = 24
        scorePopup.fontColor = .green
        
        // Convert goal position to camera coordinates
        let goalPositionInCamera = convert(goalNode.position, to: camera!)
        scorePopup.position = goalPositionInCamera
        scorePopup.zPosition = 25
        camera?.addChild(scorePopup)
        
        // Animate the score popup
        let moveUp = SKAction.moveBy(x: 0, y: 40, duration: 0.8)
        let fadeOut = SKAction.fadeOut(withDuration: 0.8)
        let scaleUp = SKAction.scale(to: 1.5, duration: 0.8)
        scorePopup.run(SKAction.group([moveUp, fadeOut, scaleUp]), completion: {
            scorePopup.removeFromParent()
        })
        
        // Remove particle effect after delay
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.run { emitter.particleBirthRate = 0 },
            SKAction.wait(forDuration: 1.5),
            SKAction.removeFromParent()
        ]))
        
        // Add a camera shake effect
        if let camera = self.camera {
            let shakeAction = SKAction.sequence([
                SKAction.moveBy(x: 5, y: 5, duration: 0.05),
                SKAction.moveBy(x: -10, y: -10, duration: 0.05),
                SKAction.moveBy(x: 10, y: -5, duration: 0.05),
                SKAction.moveBy(x: -5, y: 10, duration: 0.05),
                SKAction.moveBy(x: 0, y: 0, duration: 0.05)
            ])
            camera.run(shakeAction)
        }
        
        // Play goal reached sound
        SoundManager.shared.playSound(name: "goal_reached", volume: 1.0)
        
        // Check if all goals collected
        let remainingGoals = goals.filter { !$0.isHidden }
        if remainingGoals.isEmpty {
            // Level completed - advance to next level
            advanceToNextLevel()
        }
    }
    
    // MARK: - Level Management
    private func loadLevel(_ level: Int) {
        // Clear previous level elements
        clearLevel()
        
        // Update level label
        levelLabel?.text = "LEVEL: \(level)"
        currentLevel = level
        
        // Get level definition
        let levelDefinition = getLevelDefinition(for: level)
        
        // Set time limit
        timeRemaining = levelDefinition.timeLimit
        
        // Create maze walls
        for wall in levelDefinition.walls {
            createMazeWall(at: wall.position, size: wall.size)
        }
        
        // Create goals
        for goalPosition in levelDefinition.goalPositions {
            createGoal(at: goalPosition, radius: 25)
        }
        
        // Set marble position
        if let marble = marble {
            marble.position = levelDefinition.startPosition
            marble.physicsBody?.velocity = .zero
            marble.physicsBody?.angularVelocity = 0
        }
    }
    
    private func clearLevel() {
        // Remove all maze walls
        for wall in mazeWalls {
            wall.removeFromParent()
        }
        mazeWalls.removeAll()
        
        // Remove all goals
            for goal in goals {
            goal.removeFromParent()
        }
        goals.removeAll()
        
        // Remove all obstacles
        for obstacle in obstacles {
            obstacle.removeFromParent()
        }
        obstacles.removeAll()
    }
    
    private func getLevelDefinition(for level: Int) -> MazeLevel {
        let screenWidth = size.width
        let screenHeight = size.height
        
        print("Creating level \(level) with screen size: \(screenWidth) x \(screenHeight)")
        
        switch level {
        case 1:
            // Simple maze with a few walls
            return MazeLevel(
                number: 1,
                walls: [
                    // Horizontal walls
                    MazeLevel.Wall(x: screenWidth/2, y: screenHeight/3, length: screenWidth/2, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth/4, y: screenHeight*2/3, length: screenWidth/2, isHorizontal: true),
                    
                    // Vertical walls
                    MazeLevel.Wall(x: screenWidth/3, y: screenHeight/2, length: screenHeight/3, isHorizontal: false),
                    MazeLevel.Wall(x: screenWidth*2/3, y: screenHeight/2, length: screenHeight/3, isHorizontal: false)
                ],
                goalPositions: [
                    CGPoint(x: screenWidth - 50, y: screenHeight - 50)
                ],
                startPosition: CGPoint(x: 50, y: 50),
                timeLimit: 30,
                difficulty: 1.0,
                timeBonus: 10
            )
            
        case 2:
            // Completely redesigned level 2 with guaranteed paths to all goals
            // Using a much simpler design with clear paths
            print("Creating simplified level 2 with guaranteed paths")
            
            let walls = [
                // Top wall with large gap on right
                MazeLevel.Wall(x: screenWidth*0.3, y: screenHeight*0.85, length: screenWidth*0.6, isHorizontal: true),
                
                // Bottom wall with large gap on left
                MazeLevel.Wall(x: screenWidth*0.7, y: screenHeight*0.15, length: screenWidth*0.6, isHorizontal: true),
                
                // Middle horizontal divider with gap
                MazeLevel.Wall(x: screenWidth*0.3, y: screenHeight*0.5, length: screenWidth*0.6, isHorizontal: true),
                
                // Left vertical wall with gap at bottom
                MazeLevel.Wall(x: screenWidth*0.25, y: screenHeight*0.65, length: screenHeight*0.4, isHorizontal: false),
                
                // Right vertical wall with gap at top
                MazeLevel.Wall(x: screenWidth*0.75, y: screenHeight*0.35, length: screenHeight*0.4, isHorizontal: false),
            ]
            
            // Log the wall positions and sizes for debugging
            for (index, wall) in walls.enumerated() {
                print("Wall \(index): position=(\(wall.position.x), \(wall.position.y)), size=(\(wall.size.width), \(wall.size.height)), isHorizontal=\(wall.isHorizontal)")
            }
            
            let goalPositions = [
                CGPoint(x: screenWidth - 50, y: screenHeight - 50),  // Top-right goal
                CGPoint(x: screenWidth/2, y: screenHeight/2)         // Center goal
            ]
            
            // Log the goal positions
            for (index, goal) in goalPositions.enumerated() {
                print("Goal \(index): position=(\(goal.x), \(goal.y))")
            }
            
            let startPosition = CGPoint(x: 50, y: 50)
            print("Start position: (\(startPosition.x), \(startPosition.y))")
            
            // Validate the maze before returning
            let isValid = validateMaze(walls: walls, startPosition: startPosition, goalPositions: goalPositions)
            print("Level 2 maze validation result: \(isValid ? "VALID" : "INVALID")")
            
            return MazeLevel(
                number: 2,
                walls: walls,
                goalPositions: goalPositions,
                startPosition: startPosition,
                timeLimit: 45,
                difficulty: 1.5,
                timeBonus: 15
            )
            
        case 3:
            // Advanced maze with more complex pattern
            return MazeLevel(
                number: 3,
                walls: [
                    // Outer frame
                    MazeLevel.Wall(x: screenWidth/2, y: screenHeight/6, length: screenWidth*0.8, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth/2, y: screenHeight*5/6, length: screenWidth*0.8, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth/6, y: screenHeight/2, length: screenHeight*0.8, isHorizontal: false),
                    MazeLevel.Wall(x: screenWidth*5/6, y: screenHeight/2, length: screenHeight*0.8, isHorizontal: false),
                    
                    // Inner maze
                    MazeLevel.Wall(x: screenWidth/3, y: screenHeight/3, length: screenWidth/6, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth*2/3, y: screenHeight/3, length: screenWidth/6, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth/3, y: screenHeight*2/3, length: screenWidth/6, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth*2/3, y: screenHeight*2/3, length: screenWidth/6, isHorizontal: true),
                    
                    MazeLevel.Wall(x: screenWidth/3, y: screenHeight/2, length: screenHeight/6, isHorizontal: false),
                    MazeLevel.Wall(x: screenWidth*2/3, y: screenHeight/2, length: screenHeight/6, isHorizontal: false),
                    
                    // Center cross
                    MazeLevel.Wall(x: screenWidth/2, y: screenHeight/2, length: screenWidth/4, isHorizontal: true),
                    MazeLevel.Wall(x: screenWidth/2, y: screenHeight/2, length: screenHeight/4, isHorizontal: false)
                ],
                goalPositions: [
                    CGPoint(x: screenWidth - 50, y: screenHeight - 50),
                    CGPoint(x: 50, y: screenHeight - 50),
                    CGPoint(x: screenWidth - 50, y: 50)
                ],
                startPosition: CGPoint(x: 50, y: 50),
                timeLimit: 60,
                difficulty: 2.0,
                timeBonus: 20
            )
            
        case 4:
            // Level 4: Concentric Rings Maze
            // This creates a challenging maze with concentric rings and specific pathways between them
            print("Creating level 4: Concentric Rings")
            
            // Create the outer ring
            let outerRingWalls = [
                // Top wall with gap
                MazeLevel.Wall(x: screenWidth*0.3, y: screenHeight*0.85, length: screenWidth*0.6, isHorizontal: true),
                MazeLevel.Wall(x: screenWidth*0.85, y: screenHeight*0.85, length: screenWidth*0.3, isHorizontal: true),
                
                // Bottom wall with gap
                MazeLevel.Wall(x: screenWidth*0.15, y: screenHeight*0.15, length: screenWidth*0.3, isHorizontal: true),
                MazeLevel.Wall(x: screenWidth*0.7, y: screenHeight*0.15, length: screenWidth*0.6, isHorizontal: true),
                
                // Left wall with gap
                MazeLevel.Wall(x: screenWidth*0.15, y: screenHeight*0.3, length: screenHeight*0.3, isHorizontal: false),
                MazeLevel.Wall(x: screenWidth*0.15, y: screenHeight*0.7, length: screenHeight*0.3, isHorizontal: false),
                
                // Right wall with gap
                MazeLevel.Wall(x: screenWidth*0.85, y: screenHeight*0.15, length: screenHeight*0.3, isHorizontal: false),
                MazeLevel.Wall(x: screenWidth*0.85, y: screenHeight*0.7, length: screenHeight*0.3, isHorizontal: false),
            ]
            
            // Create the middle ring
            let middleRingWalls = [
                // Top wall with gap
                MazeLevel.Wall(x: screenWidth*0.65, y: screenHeight*0.65, length: screenWidth*0.3, isHorizontal: true),
                MazeLevel.Wall(x: screenWidth*0.35, y: screenHeight*0.65, length: screenWidth*0.2, isHorizontal: true),
                
                // Bottom wall with gap
                MazeLevel.Wall(x: screenWidth*0.35, y: screenHeight*0.35, length: screenWidth*0.2, isHorizontal: true),
                MazeLevel.Wall(x: screenWidth*0.65, y: screenHeight*0.35, length: screenWidth*0.3, isHorizontal: true),
                
                // Left wall with gap
                MazeLevel.Wall(x: screenWidth*0.35, y: screenHeight*0.45, length: screenHeight*0.2, isHorizontal: false),
                
                // Right wall with gap
                MazeLevel.Wall(x: screenWidth*0.65, y: screenHeight*0.55, length: screenHeight*0.2, isHorizontal: false),
            ]
            
            // Create the inner obstacles
            let innerObstacles = [
                MazeLevel.Wall(x: screenWidth*0.5, y: screenHeight*0.5, length: screenWidth*0.15, isHorizontal: true),
                MazeLevel.Wall(x: screenWidth*0.5, y: screenHeight*0.5, length: screenHeight*0.15, isHorizontal: false),
            ]
            
            // Combine all walls
            let walls = outerRingWalls + middleRingWalls + innerObstacles
            
            // Create multiple goals that require navigating through the rings
            let goalPositions = [
                CGPoint(x: screenWidth*0.5, y: screenHeight*0.5),  // Center goal
                CGPoint(x: screenWidth*0.85, y: screenHeight*0.85), // Outer corner goal
                CGPoint(x: screenWidth*0.15, y: screenHeight*0.85), // Another outer corner
                CGPoint(x: screenWidth*0.85, y: screenHeight*0.15)  // Another outer corner
            ]
            
            let startPosition = CGPoint(x: screenWidth*0.15, y: screenHeight*0.15)
            
            // Validate the maze
            let isValid = validateMaze(walls: walls, startPosition: startPosition, goalPositions: goalPositions)
            print("Level 4 maze validation result: \(isValid ? "VALID" : "INVALID")")
            
            return MazeLevel(
                number: 4,
                walls: walls,
                goalPositions: goalPositions,
                startPosition: startPosition,
                timeLimit: 75,
                difficulty: 2.5,
                timeBonus: 25
            )
            
        case 5:
            // Level 5: Spiral Maze
            // This creates a challenging spiral pattern that requires careful navigation
            print("Creating level 5: Spiral Maze")
            
            var walls: [MazeLevel.Wall] = []
            
            // Create a spiral pattern
            let center = CGPoint(x: screenWidth/2, y: screenHeight/2)
            let maxRadius = min(screenWidth, screenHeight) * 0.4
            let spiralGap = 60.0 // Gap between spiral walls
            
            // Create spiral segments
            for i in 0..<4 {
                let radius = maxRadius - CGFloat(i) * spiralGap
                let startAngle = CGFloat(i) * .pi / 2
                let endAngle = startAngle + .pi * 1.5
                
                // Create a spiral segment (approximated with straight walls)
                let segments = 12
                for j in 0..<segments {
                    let angle1 = startAngle + CGFloat(j) * (endAngle - startAngle) / CGFloat(segments)
                    let angle2 = startAngle + CGFloat(j+1) * (endAngle - startAngle) / CGFloat(segments)
                    
                    let x1 = center.x + cos(angle1) * radius
                    let y1 = center.y + sin(angle1) * radius
                    let x2 = center.x + cos(angle2) * radius
                    let y2 = center.y + sin(angle2) * radius
                    
                    // Skip the last segment of each spiral to create an entrance
                    if j < segments - 1 || i == 3 {
                        // Calculate wall position and length
                        let wallX = (x1 + x2) / 2
                        let wallY = (y1 + y2) / 2
                        let dx = x2 - x1
                        let dy = y2 - y1
                        let length = sqrt(dx*dx + dy*dy)
                        let isHorizontal = abs(dx) > abs(dy)
                        
                        walls.append(MazeLevel.Wall(x: wallX, y: wallY, length: length, isHorizontal: isHorizontal))
                    }
                }
            }
            
            // Add some cross barriers to make navigation more challenging
            walls.append(MazeLevel.Wall(x: center.x + maxRadius*0.3, y: center.y, length: spiralGap*1.5, isHorizontal: true))
            walls.append(MazeLevel.Wall(x: center.x - maxRadius*0.3, y: center.y, length: spiralGap*1.5, isHorizontal: true))
            walls.append(MazeLevel.Wall(x: center.x, y: center.y + maxRadius*0.3, length: spiralGap*1.5, isHorizontal: false))
            walls.append(MazeLevel.Wall(x: center.x, y: center.y - maxRadius*0.3, length: spiralGap*1.5, isHorizontal: false))
            
            // Create goals that require navigating through the spiral
            let goalPositions = [
                center,  // Center goal (hardest to reach)
                CGPoint(x: center.x + maxRadius*0.5, y: center.y + maxRadius*0.5),
                CGPoint(x: center.x - maxRadius*0.5, y: center.y - maxRadius*0.5),
                CGPoint(x: center.x - maxRadius*0.5, y: center.y + maxRadius*0.5),
                CGPoint(x: center.x + maxRadius*0.5, y: center.y - maxRadius*0.5)
            ]
            
            let startPosition = CGPoint(x: center.x + maxRadius + 30, y: center.y)
            
            // Validate the maze
            let isValid = validateMaze(walls: walls, startPosition: startPosition, goalPositions: goalPositions)
            print("Level 5 maze validation result: \(isValid ? "VALID" : "INVALID")")
            
            return MazeLevel(
                number: 5,
                walls: walls,
                goalPositions: goalPositions,
                startPosition: startPosition,
                timeLimit: 90,
                difficulty: 3.0,
                timeBonus: 30
            )
            
        default:
            // If we run out of levels, create a random maze with increasing difficulty
            let difficulty = min(5.0, 1.0 + Float(level - 5) * 0.5) // Gradually increase difficulty up to 5.0
            let timeBonus = min(50, 10 + (level - 1) * 5) // Gradually increase time bonus up to 50
            return createRandomMaze(level: level, difficulty: difficulty, timeBonus: timeBonus)
        }
    }
    
    private func createRandomMaze(level: Int, difficulty: Float = 1.0, timeBonus: Int = 0) -> MazeLevel {
        let screenWidth = size.width
        let screenHeight = size.height
        
        // Define start and goal positions
        let startPosition = CGPoint(x: 50, y: 50)
        let mainGoalPosition = CGPoint(x: screenWidth - 50, y: screenHeight - 50)
        
        // Create goal positions - scale with level
        let goalCount = min(level, 4) // Maximum 4 goals
        var goalPositions: [CGPoint] = [mainGoalPosition]
        
        // Add additional goals based on level
        if goalCount > 1 {
            goalPositions.append(CGPoint(x: screenWidth/2, y: screenHeight/2))
        }
        if goalCount > 2 {
            goalPositions.append(CGPoint(x: 50, y: screenHeight - 50))
        }
        if goalCount > 3 {
            goalPositions.append(CGPoint(x: screenWidth - 50, y: 50))
        }
        
        // Keep generating mazes until we find a valid one
        var attempts = 0
        var walls: [MazeLevel.Wall] = []
        var isValidMaze = false
        
        while !isValidMaze && attempts < 20 {
            attempts += 1
            walls.removeAll()
            
            // Create walls in a more structured way
            // Scale number of walls with difficulty
            let wallCount = Int(6.0 + Float(level) * difficulty)
            
            // First create some horizontal walls
            for i in 1..<min(wallCount/2 + 1, 6) {
                let y = screenHeight * CGFloat(i) / CGFloat(min(wallCount/2 + 1, 6) + 1)
                let length = screenWidth * CGFloat.random(in: 0.3...0.6)
                let x = screenWidth * CGFloat.random(in: 0.2...0.8)
                
                // Ensure walls have gaps
                if i % 2 == 0 {
                    walls.append(MazeLevel.Wall(x: x, y: y, length: length, isHorizontal: true))
                } else {
                    walls.append(MazeLevel.Wall(x: screenWidth - x, y: y, length: length, isHorizontal: true))
                }
            }
            
            // Then create some vertical walls
            for i in 1..<min(wallCount/2 + 1, 6) {
                let x = screenWidth * CGFloat(i) / CGFloat(min(wallCount/2 + 1, 6) + 1)
                let length = screenHeight * CGFloat.random(in: 0.3...0.6)
                let y = screenHeight * CGFloat.random(in: 0.2...0.8)
                
                // Ensure walls have gaps
                if i % 2 == 0 {
                    walls.append(MazeLevel.Wall(x: x, y: y, length: length, isHorizontal: false))
                } else {
                    walls.append(MazeLevel.Wall(x: x, y: screenHeight - y, length: length, isHorizontal: false))
                }
            }
            
            // Ensure walls aren't placed too close to start or goals
            let safeDistance: CGFloat = 60
            walls = walls.filter { wall in
                // Check start position
                if distance(from: wall.position, to: startPosition) < safeDistance {
                    return false
                }
                
                // Check goal positions
                for goalPos in goalPositions {
                    if distance(from: wall.position, to: goalPos) < safeDistance {
                        return false
                    }
                }
                
                return true
            }
            
            // Validate the maze to ensure all goals are reachable
            isValidMaze = validateMaze(walls: walls, startPosition: startPosition, goalPositions: goalPositions)
        }
        
        // If we couldn't generate a valid maze, create a simple one
        if !isValidMaze {
            walls = createSimpleMaze(level: level)
        }
        
        // Calculate time limit based on level and difficulty
        let baseTime = 30
        let timePerGoal = 10
        let timeLimit = baseTime + goalCount * timePerGoal + Int(Float(level) * 2.0)
        
        return MazeLevel(
            number: level,
            walls: walls,
            goalPositions: goalPositions,
            startPosition: startPosition,
            timeLimit: timeLimit,
            difficulty: difficulty,
            timeBonus: timeBonus
        )
    }
    
    // Helper function to calculate distance between two points
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx*dx + dy*dy)
    }
    
    // Validate that all goals are reachable from the start position
    private func validateMaze(walls: [MazeLevel.Wall], startPosition: CGPoint, goalPositions: [CGPoint]) -> Bool {
        print("Validating maze with \(walls.count) walls and \(goalPositions.count) goals")
        
        // Use a finer grid for better path detection
        let gridSize: CGFloat = 10
        let cols = Int(size.width / gridSize)
        let rows = Int(size.height / gridSize)
        
        print("Grid size: \(rows) rows x \(cols) columns (cell size: \(gridSize)px)")
        
        // Create a grid representation of the maze
        var grid = Array(repeating: Array(repeating: true, count: cols), count: rows)
        
        // Mark walls as blocked cells with a slightly wider margin
        for (index, wall) in walls.enumerated() {
            // Add a small buffer around walls to ensure paths are navigable
            let wallRect = CGRect(
                x: wall.position.x - wall.size.width/2 - 15, // Increased buffer for marble size
                y: wall.position.y - wall.size.height/2 - 15, // Increased buffer for marble size
                width: wall.size.width + 30, // Doubled buffer (was 10)
                height: wall.size.height + 30 // Doubled buffer (was 10)
            )
            
            print("Wall \(index) rect: origin=(\(wallRect.origin.x), \(wallRect.origin.y)), size=(\(wallRect.size.width), \(wallRect.size.height))")
            
            // Mark all grid cells that intersect with the wall as blocked
            var blockedCells = 0
            for row in 0..<rows {
                for col in 0..<cols {
                    let cellRect = CGRect(
                        x: CGFloat(col) * gridSize,
                        y: CGFloat(row) * gridSize,
                        width: gridSize,
                        height: gridSize
                    )
                    
                    if wallRect.intersects(cellRect) {
                        grid[row][col] = false
                        blockedCells += 1
                    }
                }
            }
            print("Wall \(index) blocked \(blockedCells) cells")
        }
        
        // Convert positions to grid coordinates
        func toGridCoord(_ position: CGPoint) -> (row: Int, col: Int) {
            let col = min(max(Int(position.x / gridSize), 0), cols - 1)
            let row = min(max(Int(position.y / gridSize), 0), rows - 1)
            return (row, col)
        }
        
        // Check if there's a path from start to each goal
        let startCoord = toGridCoord(startPosition)
        print("Start grid coordinate: row=\(startCoord.row), col=\(startCoord.col)")
        
        for (goalIndex, goalPosition) in goalPositions.enumerated() {
            let goalCoord = toGridCoord(goalPosition)
            print("Goal \(goalIndex) grid coordinate: row=\(goalCoord.row), col=\(goalCoord.col)")
            
            // Skip if start or goal is in a blocked cell
            if !grid[startCoord.row][startCoord.col] {
                print("ERROR: Start position is in a blocked cell!")
                return false
            }
            
            if !grid[goalCoord.row][goalCoord.col] {
                print("ERROR: Goal \(goalIndex) is in a blocked cell!")
                return false
            }
            
            // Use breadth-first search to find a path
            var visited = Array(repeating: Array(repeating: false, count: cols), count: rows)
            var queue = [(startCoord.row, startCoord.col)]
            visited[startCoord.row][startCoord.col] = true
            
            var foundPath = false
            var cellsExplored = 0
            
            print("Starting BFS path search to goal \(goalIndex)")
            
            while !queue.isEmpty && !foundPath {
                let (r, c) = queue.removeFirst()
                cellsExplored += 1
                
                // Check if we've reached the goal
                if r == goalCoord.row && c == goalCoord.col {
                    foundPath = true
                    print("Path found to goal \(goalIndex) after exploring \(cellsExplored) cells")
                    break
                }
                
                // Try all four directions
                let directions = [(0, 1), (1, 0), (0, -1), (-1, 0)]
                
                for (dr, dc) in directions {
                    let nr = r + dr
                    let nc = c + dc
                    
                    // Check if the new position is valid
                    if nr >= 0 && nr < rows && nc >= 0 && nc < cols && grid[nr][nc] && !visited[nr][nc] {
                        visited[nr][nc] = true
                        queue.append((nr, nc))
                    }
                }
            }
            
            // If no path was found to this goal, the maze is invalid
            if !foundPath {
                print("ERROR: No path found to goal \(goalIndex) after exploring \(cellsExplored) cells")
                return false
            }
        }
        
        // All goals are reachable
        print("Maze validation successful - all goals are reachable")
        return true
    }
    
    // Create a simple, guaranteed-solvable maze
    private func createSimpleMaze(level: Int) -> [MazeLevel.Wall] {
        let screenWidth = size.width
        let screenHeight = size.height
        
        var walls: [MazeLevel.Wall] = []
        
        // Create a simple maze pattern that ensures a path exists
        switch level % 3 {
        case 0:
            // Zigzag pattern
            for i in 1..<5 {
                let y = screenHeight * CGFloat(i) / 6
                let length = screenWidth * 0.7
                let x = i % 2 == 0 ? screenWidth * 0.65 : screenWidth * 0.35
                
                walls.append(MazeLevel.Wall(x: x, y: y, length: length, isHorizontal: true))
            }
        case 1:
            // Spiral-like pattern
            let centerX = screenWidth / 2
            let centerY = screenHeight / 2
            
            walls.append(MazeLevel.Wall(x: centerX, y: centerY * 0.5, length: screenWidth * 0.7, isHorizontal: true))
            walls.append(MazeLevel.Wall(x: centerX, y: centerY * 1.5, length: screenWidth * 0.7, isHorizontal: true))
            walls.append(MazeLevel.Wall(x: centerX * 0.5, y: centerY, length: screenHeight * 0.7, isHorizontal: false))
            walls.append(MazeLevel.Wall(x: centerX * 1.5, y: centerY, length: screenHeight * 0.7, isHorizontal: false))
            
            // Add some small walls for complexity
            walls.append(MazeLevel.Wall(x: centerX * 0.8, y: centerY * 0.8, length: screenWidth * 0.2, isHorizontal: true))
            walls.append(MazeLevel.Wall(x: centerX * 1.2, y: centerY * 1.2, length: screenHeight * 0.2, isHorizontal: false))
        case 2:
            // Grid pattern with gaps
            let spacing = screenWidth / 5
            
            for i in 1..<4 {
                // Horizontal walls with gaps
                let y = screenHeight * CGFloat(i) / 4
                let gap = CGFloat(i % 3) * spacing
                
                walls.append(MazeLevel.Wall(x: spacing, y: y, length: spacing * 1.5, isHorizontal: true))
                walls.append(MazeLevel.Wall(x: spacing * 3.5, y: y, length: spacing * 1.5, isHorizontal: true))
                
                // Vertical walls with gaps
                let x = screenWidth * CGFloat(i) / 4
                let vGap = CGFloat((i + 1) % 3) * spacing
                
                walls.append(MazeLevel.Wall(x: x, y: spacing, length: spacing * 1.5, isHorizontal: false))
                walls.append(MazeLevel.Wall(x: x, y: spacing * 3.5, length: spacing * 1.5, isHorizontal: false))
            }
        default:
            break
        }
        
        return walls
    }
    
    private func createMazeWall(at position: CGPoint, size: CGSize) {
        // Create main wall node
        let wall = SKSpriteNode(color: .white, size: size)
        wall.position = position
        wall.zPosition = 5
        
        // Add pixel art texture
        wall.texture = SKTexture(image: createPixelArtWall(size: size, isHorizontal: size.width > size.height))
        
        // Physics
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.obstacle
        body.collisionBitMask = PhysicsCategory.marble
        wall.physicsBody = body
        
        addChild(wall)
        mazeWalls.append(wall)
    }
    
    private func createPixelArtWall(size: CGSize, isHorizontal: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Dark background
            UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            // Draw pixel pattern
            let pixelSize: CGFloat = 4.0
            
            // Create a concrete/metal wall look
            for x in stride(from: 0, to: size.width, by: pixelSize) {
                for y in stride(from: 0, to: size.height, by: pixelSize) {
                    // Random noise pattern for concrete texture
                    let randomValue = CGFloat(arc4random_uniform(100)) / 100.0
                    let brightness = 0.2 + randomValue * 0.15
                    
                    // Add edge highlight
                    var edgeHighlight: CGFloat = 0.0
                    
                    if isHorizontal {
                        // Top edge highlight for horizontal walls
                        if y < pixelSize * 2 {
                            edgeHighlight = 0.15
                        }
                        // Bottom edge shadow
                        else if y > size.height - pixelSize * 2 {
                            edgeHighlight = -0.1
                        }
                    } else {
                        // Left edge highlight for vertical walls
                        if x < pixelSize * 2 {
                            edgeHighlight = 0.15
                        }
                        // Right edge shadow
                        else if x > size.width - pixelSize * 2 {
                            edgeHighlight = -0.1
                        }
                    }
                    
                    UIColor(red: brightness + edgeHighlight, 
                           green: brightness + edgeHighlight, 
                           blue: brightness + edgeHighlight * 1.2, 
                           alpha: 1.0).setFill()
                    
                    context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                }
            }
        }
    }
    
    private func createGoal(at position: CGPoint, radius: CGFloat) {
        let goal = SKShapeNode(circleOfRadius: radius)
        goal.position = position
        goal.fillColor = .clear
        goal.strokeColor = .green
        goal.lineWidth = 1
        goal.name = "goal"
        
        // Add pixel art pattern
        let dotNode = SKSpriteNode(texture: SKTexture(image: createPixelArtGoal(radius: radius)))
        dotNode.size = CGSize(width: radius*2, height: radius*2)
        goal.addChild(dotNode)
        
        // Simple pulsing animation
        let scaleUp = SKAction.scale(to: 1.05, duration: 0.5)
        let scaleDown = SKAction.scale(to: 0.95, duration: 0.5)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        goal.run(SKAction.repeatForever(pulse))
        
        // Physics (sensor)
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.goal
        body.collisionBitMask = 0 // No collision, just detection
        body.contactTestBitMask = PhysicsCategory.marble
        goal.physicsBody = body
        
        addChild(goal)
        goals.append(goal)
    }
    
    private func createPixelArtGoal(radius: CGFloat) -> UIImage {
        let size = CGSize(width: radius*2, height: radius*2)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Transparent background
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            // Draw pixel art pattern in a circle
            let pixelSize: CGFloat = 3.0
            let centerX = size.width / 2
            let centerY = size.height / 2
            
            // Create a glowing effect
            for x in stride(from: 0, to: size.width, by: pixelSize) {
                for y in stride(from: 0, to: size.height, by: pixelSize) {
                    // Only draw pixels within the circle
                    let dx = x + pixelSize/2 - centerX
                    let dy = y + pixelSize/2 - centerY
                    let distanceFromCenter = sqrt(dx*dx + dy*dy)
                    
                    if distanceFromCenter <= radius {
                        // Create a glowing effect that's brighter in the center
                        let normalizedDistance = distanceFromCenter / radius
                        let brightness = 1.0 - normalizedDistance
                        
                        // Neon green glow
                        UIColor(red: 0.0, 
                               green: 0.8 * brightness, 
                               blue: 0.2 * brightness, 
                               alpha: 0.7 * brightness).setFill()
                        
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
            
            // Add a brighter center
            let centerGlowRadius = radius * 0.3
            for x in stride(from: centerX - centerGlowRadius, to: centerX + centerGlowRadius, by: pixelSize) {
                for y in stride(from: centerY - centerGlowRadius, to: centerY + centerGlowRadius, by: pixelSize) {
                    let dx = x + pixelSize/2 - centerX
                    let dy = y + pixelSize/2 - centerY
                    let distanceFromCenter = sqrt(dx*dx + dy*dy)
                    
                    if distanceFromCenter <= centerGlowRadius {
                        // Bright center
                        UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 0.9).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
        }
    }
    
    // MARK: - Haptic Feedback
    private func triggerHapticFeedback(intensity: CGFloat) {
        // Removed haptic feedback functionality to improve performance
        
        // Only play rolling sound with volume based on intensity (made much quieter)
        SoundManager.shared.playSound(name: "marble_roll", volume: Float(intensity * 0.1))
    }
    
    private func triggerCollisionHaptic() {
        // Removed haptic feedback functionality to improve performance
        
        // Calculate collision force for debugging
        let velocity = marble?.physicsBody?.velocity ?? CGVector.zero
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        print("Collision detected with speed: \(speed)")
        
        // Calculate volume based on collision force
        let collisionForce = marble?.physicsBody?.velocity.dx ?? 0
        let volume = min(Float(abs(collisionForce) / 100), 1.0)
        
        // Play collision sound
        SoundManager.shared.playSound(name: "marble_collision", volume: 0.5 + volume * 0.5)
    }
    
    private func triggerGoalHaptic() {
        // Removed haptic feedback functionality to improve performance
        
        // Play goal reached sound
        SoundManager.shared.playSound(name: "goal_reached", volume: 1.0)
    }
    
    private func playLevelCompleteSound() {
        print("Level complete sound played")
        SoundManager.shared.playSound(name: "level_complete", volume: 1.0)
    }
    
    private func playGameOverSound() {
        print("Game over sound played")
        SoundManager.shared.playSound(name: "game_over", volume: 1.0)
    }
    
    private func playButtonClickSound() {
        print("Button click sound played")
        SoundManager.shared.playSound(name: "button_click", volume: 0.7)
    }
    
    private func createPixelArtButton(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Dark background
            UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            // Draw pixel border
            let pixelSize: CGFloat = 2.0
            let borderWidth = 4.0
            
            for x in stride(from: 0, to: size.width, by: pixelSize) {
                for y in stride(from: 0, to: size.height, by: pixelSize) {
                    // Only draw pixels near the border
                    let isTopBorder = y < borderWidth
                    let isBottomBorder = y > size.height - borderWidth
                    let isLeftBorder = x < borderWidth
                    let isRightBorder = x > size.width - borderWidth
                    
                    if isTopBorder || isLeftBorder || isBottomBorder || isRightBorder {
                        // Create a metallic border effect
                        var brightness: CGFloat = 0.5
                        
                        // Top and left edges are lighter
                        if isTopBorder || isLeftBorder {
                            brightness = 0.7
                        }
                        
                        // Bottom and right edges are darker
                        if isBottomBorder || isRightBorder {
                            brightness = 0.3
                        }
                        
                        // Corners are special
                        if (isTopBorder && isLeftBorder) || (isBottomBorder && isRightBorder) {
                            brightness = 0.6
                        }
                        
                        UIColor(white: brightness, alpha: 1.0).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
        }
    }
    
    private func createPixelArtPanel(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let context = ctx.cgContext
            
            // Dark background with slight blue tint
            UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.9).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            // Draw pixel border
            let pixelSize: CGFloat = 2.0
            let borderWidth = 4.0
            
            for x in stride(from: 0, to: size.width, by: pixelSize) {
                for y in stride(from: 0, to: size.height, by: pixelSize) {
                    // Only draw pixels near the border
                    let isTopBorder = y < borderWidth
                    let isBottomBorder = y > size.height - borderWidth
                    let isLeftBorder = x < borderWidth
                    let isRightBorder = x > size.width - borderWidth
                    
                    if isTopBorder || isLeftBorder || isBottomBorder || isRightBorder {
                        // Create a metallic border effect
                        var brightness: CGFloat = 0.5
                        
                        // Top and left edges are lighter
                        if isTopBorder || isLeftBorder {
                            brightness = 0.7
                        }
                        
                        // Bottom and right edges are darker
                        if isBottomBorder || isRightBorder {
                            brightness = 0.3
                        }
                        
                        // Corners are special
                        if (isTopBorder && isLeftBorder) || (isBottomBorder && isRightBorder) {
                            brightness = 0.6
                        }
                        
                        UIColor(white: brightness, alpha: 1.0).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                    
                    // Add some noise to the panel background
                    else if arc4random_uniform(100) < 5 {
                        let darkness = CGFloat(arc4random_uniform(10)) / 100.0
                        UIColor(red: 0.1, green: 0.1, blue: 0.15 + darkness, alpha: 1.0).setFill()
                        context.fill(CGRect(x: x, y: y, width: pixelSize, height: pixelSize))
                    }
                }
            }
        }
    }
}
